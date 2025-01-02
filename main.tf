terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}

provider "azurerm" {
  features {}
}

# Resource Group
resource "azurerm_resource_group" "fusionauth" {
  name     = var.resource_group_name
  location = var.location

  tags = {
    Environment = "Production"
    Application = "FusionAuth"
  }
}

# Network Security Group
resource "azurerm_network_security_group" "fusionauth" {
  name                = "fusionauth-nsg"
  location            = azurerm_resource_group.fusionauth.location
  resource_group_name = azurerm_resource_group.fusionauth.name

  security_rule {
    name                       = "Allow-HTTPS"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range         = "*"
    destination_port_range    = "443"
    source_address_prefix     = "*"
    destination_address_prefix = "*"
  }
}

# PostgreSQL Flexible Server
resource "azurerm_postgresql_flexible_server" "fusionauth" {
  name                = "fusionauth-db"
  resource_group_name = azurerm_resource_group.fusionauth.name
  location            = azurerm_resource_group.fusionauth.location
  version            = "16"
  
  administrator_login    = "fusionauth_admin"
  administrator_password = var.admin_password

  storage_mb = 32768
  sku_name   = "B_Standard_B2s"

  backup_retention_days        = 30
  geo_redundant_backup_enabled = true
  zone                        = "1"

  high_availability {
    mode                      = "ZoneRedundant"
    standby_availability_zone = "2"
  }

  maintenance_window {
    day_of_week  = 0
    start_hour   = 3
    start_minute = 0
  }

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = true
   # ssl_enforcement_enabled       = true
  }
}

# PostgreSQL Firewall Rules
resource "azurerm_postgresql_flexible_server_firewall_rule" "allowed_ips" {
  for_each         = toset(var.allowed_ip_ranges)
  name             = "allow-ip-${index(var.allowed_ip_ranges, each.value)}"
  server_id        = azurerm_postgresql_flexible_server.fusionauth.id
  start_ip_address = cidrhost(each.value, 0)
  end_ip_address   = cidrhost(each.value, -1)
}

# FusionAuth Database
resource "azurerm_postgresql_flexible_server_database" "fusionauth" {
  name      = "fusionauth"
  server_id = azurerm_postgresql_flexible_server.fusionauth.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Virtual Network
resource "azurerm_virtual_network" "fusionauth" {
  name                = "fusionauth-vnet"
  resource_group_name = azurerm_resource_group.fusionauth.name
  location            = azurerm_resource_group.fusionauth.location
  address_space       = ["10.0.0.0/16"]
}


resource "azurerm_subnet" "frontend" {
  name                 = "frontend"
  resource_group_name  = azurerm_resource_group.fusionauth.name
  virtual_network_name = azurerm_virtual_network.fusionauth.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "backend" {
  name                 = "backend"
  resource_group_name  = azurerm_resource_group.fusionauth.name
  virtual_network_name = azurerm_virtual_network.fusionauth.name
  address_prefixes     = ["10.0.2.0/24"]
}

# Container Instance
resource "azurerm_container_group" "fusionauth" {
  name                = "fusionauth-container"
  location            = azurerm_resource_group.fusionauth.location
  resource_group_name = azurerm_resource_group.fusionauth.name
  ip_address_type    = "Public"
  dns_name_label     = "fusionauth"
  os_type            = "Linux"

  container {
    name   = "fusionauth"
    image  = "fusionauth/fusionauth-app:1.43.0"
    cpu    = "2"
    memory = "4"

    ports {
      port     = 9011
      protocol = "TCP"
    }

    environment_variables = {
      "DATABASE_URL"               = "jdbc:postgresql://${azurerm_postgresql_flexible_server.fusionauth.fqdn}:5432/fusionauth"
      "DATABASE_USER"             = "fusionauth_admin"
      "DATABASE_PASSWORD"         = var.admin_password
      "FUSIONAUTH_APP_MEMORY"     = "3072M"
      "FUSIONAUTH_APP_RUNTIME_MODE" = "production"
      "FUSIONAUTH_APP_URL"        = "https://oauth2-server.${var.domain_name}"
      "SEARCH_TYPE"               = "elasticsearch"
    }

    liveness_probe {
      http_get {
        path = "/api/status"
        port = 9011
      }
      initial_delay_seconds = 30
      period_seconds        = 10
    }
  }
}

# Application Gateway Components
resource "azurerm_public_ip" "fusionauth" {
  name                = "fusionauth-pip"
  resource_group_name = azurerm_resource_group.fusionauth.name
  location            = azurerm_resource_group.fusionauth.location
  allocation_method   = "Static"
  sku                =  "Standard"
  zones              =   ["1", "2", "3"]
}

resource "azurerm_web_application_firewall_policy" "fusionauth" {
  name                = "fusionauth-wafpolicy"
  resource_group_name = azurerm_resource_group.fusionauth.name
  location            = azurerm_resource_group.fusionauth.location

  policy_settings {
    enabled                     = true
    mode                       = "Prevention"
    request_body_check         = true
    max_request_body_size_in_kb = 128
    file_upload_limit_in_mb    = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "OWASP"
      version = "3.2"
    }
  }
}


resource "azurerm_application_gateway" "fusionauth" {
  name                = "fusionauth-appgw"
  resource_group_name = azurerm_resource_group.fusionauth.name
  location            = azurerm_resource_group.fusionauth.location

  sku {
    name     = "WAF_v2"
    tier     = "WAF_v2"
    capacity = 2
  }

  gateway_ip_configuration {
    name      = "gateway-ip-config"
    subnet_id = azurerm_subnet.frontend.id
    #subnet_id = azurerm_virtual_network.fusionauth.subnet.*.id[0]
  }

  frontend_port {
    name = "https-port"
    port = 443
  }

  frontend_ip_configuration {
    name                 = "frontend-ip-config"
    public_ip_address_id = azurerm_public_ip.fusionauth.id
  }

  backend_address_pool {
    name         = "fusionauth-backend"
    ip_addresses = [azurerm_container_group.fusionauth.ip_address]
  }

  backend_http_settings {
    name                                = "fusionauth-http-settings"
    cookie_based_affinity               = "Disabled"
    port                               = 9011
    protocol                           = "Http"
    request_timeout                    = 60
    probe_name                         = "fusionauth-probe"
    pick_host_name_from_backend_address = true
  }

  probe {
    name                = "fusionauth-probe"
    host                = "127.0.0.1"
    interval            = 30
    timeout             = 30
    unhealthy_threshold = 3
    protocol            = "Http"
    port                = 9011
    path                = "/api/status"
  }
  
  
  http_listener {
    name                           = "fusionauth-listener"
    frontend_ip_configuration_name = "frontend-ip-config"
    frontend_port_name            = "https-port"
    protocol                      = "Https"
    ssl_certificate_name          = "fusionauth-ssl"
    require_sni                   = true
  }

  ssl_certificate {
    name     = "fusionauth-ssl"
    data     = filebase64("path/to/your/certificate.pfx")
    password = var.ssl_certificate_password
  }

  request_routing_rule {
    name                       = "fusionauth-routing"
    rule_type                 = "Basic"
    http_listener_name        = "fusionauth-listener"
    backend_address_pool_name = "fusionauth-backend"
    backend_http_settings_name = "fusionauth-http-settings"
    priority                  = 1
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S"
  }

  waf_configuration {
    enabled                  = true
    firewall_mode           = "Prevention"
    rule_set_type          = "OWASP"
    rule_set_version       = "3.2"
    file_upload_limit_mb   = 100
    request_body_check     = true
    max_request_body_size_kb = 128
  }
}

# Monitoring
resource "azurerm_monitor_action_group" "fusionauth" {
  name                = "fusionauth-actiongroup"
  resource_group_name = azurerm_resource_group.fusionauth.name
  short_name          = "fusionauth"

  email_receiver {
    name          = "admin"
    email_address = var.admin_email
  }
}


resource "azurerm_monitor_metric_alert" "cpu_alert" {
  name                = "fusionauth-cpu-alert"
  resource_group_name = azurerm_resource_group.fusionauth.name
  scopes              = [azurerm_container_group.fusionauth.id]
  description         = "Action will be triggered when CPU usage exceeds 80%"

  criteria {
    metric_namespace = "Microsoft.ContainerInstance/containerGroups"
    metric_name      = "CpuUsage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = 80
  }

  action {
    action_group_id = azurerm_monitor_action_group.fusionauth.id
  }
}