# FusionAuth Infrastructure on Azure with Terraform

## Overview
This project enables the deployment of a complete infrastructure for FusionAuth on Azure using Terraform. The infrastructure includes a highly available configuration with Application Gateway, WAF, PostgreSQL Flexible Server, and Container Instances.

## Architecture

### Main Components
- Application Gateway with WAF (Web Application Firewall)
- Azure Container Instances for FusionAuth
- Highly available PostgreSQL Flexible Server
- Virtual network with isolated subnets
- Monitoring and alerts

### Architecture Diagram
```
[Internet] --> [Application Gateway + WAF]
                        |
                [Virtual Network]
                /              \
[FusionAuth Container]    [PostgreSQL]
```

## Prerequisites

### Required Tools
- Terraform >= 1.0.0
- Azure CLI
- Active Azure subscription

### Preparation
1. Install Azure CLI and log in:
```bash
az login
```

2. Configure the Azure subscription:
```bash
az account set --subscription "Your-Subscription-ID"
```

3. Prepare an SSL certificate in PFX format.

## Project Structure

```plaintext
.
├── README.md
├── main.tf
├── variables.tf
├── outputs.tf
├── container.tf
├── database.tf
├── gateway.tf
├── monitoring.tf
└── terraform.tfvars
```

## Configuration

### 1. Required Variables
Create a `terraform.tfvars` file with the following variables:

```hcl
admin_password = "your-secure-password"
allowed_ip_ranges = ["x.x.x.x/32"]
ssl_certificate_path = "/path/to/your/certificate.pfx"
ssl_certificate_password = "certificate-password"
environment = "production"
domain_name = "your-domain.com"
admin_email = "admin@your-domain.com"
```

### 2. Optional Variables
The following variables can be customized in `variables.tf`:

| Variable              | Description                     | Default        |
|-----------------------|---------------------------------|-----------------|
| location              | Azure Region                   | westeurope      |
| resource_group_name   | Resource Group Name            | fusionauth-rg   |
| environment           | Deployment Environment          | production      |

## Deployment

### 1. Initialization
```bash
terraform init
```

### 2. Planning
```bash
terraform plan -out=tfplan
```

### 3. Applying
```bash
terraform apply tfplan
```

## Post-Deployment DNS Configuration

After deployment, configure your DNS with the public IP of the Application Gateway:

```bash
# Retrieve the IP of the Application Gateway
terraform output application_gateway_ip

# Configure the DNS
auth.your-domain.com.  IN  A  <Application-Gateway-IP>
```

## Monitoring and Maintenance

### Configured Alerts
- CPU usage > 80%
- Memory usage > 80%
- Email notifications

### Maintenance
1. Update the infrastructure:
```bash
terraform plan
terraform apply
```

2. Destroy the infrastructure:
```bash
terraform destroy
```

## Security

### Implemented Measures
- WAF with OWASP rules 3.2
- Forced SSL/TLS
- Isolated networks
- PostgreSQL firewall
- Strong authentication

### Best Practices
- Regular password rotation
- Regular updates of container images
- Monitoring WAF logs
- Periodic review of security rules

## High Availability

### Redundant Components
- PostgreSQL in ZoneRedundant configuration
- Application Gateway in multiple zones
- Geo-redundant backup for PostgreSQL

## Troubleshooting

### Common Issues

1. Connection failure to PostgreSQL
```bash
# Check the server status
az postgres flexible-server show --name fusionauth-db --resource-group fusionauth-rg
```

2. Application Gateway issues
```bash
# Check health status
az network application-gateway show-backend-health \
    --name fusionauth-appgw \
    --resource-group fusionauth-rg
```

3. Container issues
```bash
# Check container logs
az container logs \
    --name fusionauth-container \
    --resource-group fusionauth-rg
```

## Costs

### Main Components
- Application Gateway WAF_v2: ~€200/month
- PostgreSQL Flexible Server: ~€100/month
- Container Instances: ~€50/month
- Others (storage, networking): ~€20/month

### Possible Optimizations
- Reduce capacity in non-prod environments
- Autoscaling
- Capacity reservations for discounts

## Support and Contribution

### Support
For any questions or issues:
1. Open an issue on the repository
2. Contact the DevOps team
3. Check the Azure documentation

### Contribution
1. Fork the repository
2. Create a branch for the feature
3. Submit a Pull Request

## License
This project is licensed under the MIT License. See the LICENSE file for more details.

## Authors and Maintenance
Maintained by the SYNTHI AI DevOps team.

---

**Note**: This README is a living document. Feel free to update it based on your needs and feedback.
