locals {
  common_tags = {
    Environment = "Production"
    Project     = "FusionAuth"
    ManagedBy   = "Terraform"
    Owner       = var.admin_email
  }

  backup_time_window = {
    start_hour   = 3
    start_minute = 0
    duration     = "PT12H"  # 4 heures
  }

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}