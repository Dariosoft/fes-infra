# Hostinger Preparation

The Hostinger overlay and Terraform code are templates and are not applied automatically.

Before deployment:

1. Contract or select a VPS in Brazil and measure latency from Argentina.
2. Replace `REPLACE_GITHUB_OWNER`, `REPLACE_BASE_DOMAIN` and `REPLACE_EMAIL`.
3. Publish multi-architecture application images to GHCR.
4. Install K3s and cert-manager.
5. Create encrypted SOPS secrets.
6. Point DNS records at the VPS IPv4 address.
7. Render and inspect `kustomize build kubernetes/overlays/hostinger`.
8. Apply the overlay and verify every rollout.

Terraform is disabled by default because applying an enabled Hostinger VPS resource can purchase a subscription, while destroying it can cancel that subscription. Review the provider behavior and plan output before changing `enable_vps_provisioning`.
