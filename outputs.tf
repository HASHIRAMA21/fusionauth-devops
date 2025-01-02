output "fusionauth_url" {
  value = "https://oauth2-server.${var.domain_name}"
}

output "database_fqdn" {
  value = azurerm_postgresql_flexible_server.fusionauth.fqdn
}

output "application_gateway_ip" {
  value = azurerm_public_ip.fusionauth.ip_address
}

output "waf_policy_id" {
  value = azurerm_web_application_firewall_policy.fusionauth.id
}