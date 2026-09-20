# Hostinger Terraform Template

This module is inert by default. With `enable_vps_provisioning = false`, it creates no billable resources.

Before enabling it, retrieve valid plan, data center and Ubuntu LTS template IDs from the Hostinger API. Export `HOSTINGER_API_TOKEN`, copy `terraform.tfvars.example` to `terraform.tfvars`, and review `terraform plan` carefully.

The provider cancels the subscription when a managed VPS is destroyed. `prevent_destroy` intentionally blocks normal destruction. Existing VPS instances can be adopted with:

```bash
terraform import 'hostinger_vps.friendly_e_shop[0]' VPS_ID
```

Never commit `terraform.tfvars`, state files or API tokens.
