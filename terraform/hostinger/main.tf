locals {
  provision_count = var.enable_vps_provisioning ? 1 : 0
}

resource "hostinger_vps_ssh_key" "friendly_e_shop" {
  count = local.provision_count
  name  = "friendly-e-shop-deployer"
  key   = var.ssh_public_key

  lifecycle {
    precondition {
      condition     = length(trimspace(var.ssh_public_key)) > 0
      error_message = "ssh_public_key must be set before VPS provisioning is enabled."
    }
  }
}

resource "hostinger_vps_post_install_script" "k3s" {
  count   = local.provision_count
  name    = "friendly-e-shop-k3s-bootstrap"
  content = file("${path.module}/scripts/bootstrap-k3s.sh")
}

resource "hostinger_vps" "friendly_e_shop" {
  count                  = local.provision_count
  plan                   = var.plan
  data_center_id         = var.data_center_id
  template_id            = var.template_id
  hostname               = var.hostname
  password               = var.root_password
  ssh_key_ids            = [hostinger_vps_ssh_key.friendly_e_shop[0].id]
  post_install_script_id = hostinger_vps_post_install_script.k3s[0].id

  lifecycle {
    prevent_destroy = true
    precondition {
      condition     = var.data_center_id > 0 && var.template_id > 0 && !startswith(var.plan, "REPLACE_")
      error_message = "Replace plan, data_center_id and template_id with values returned by the Hostinger API."
    }
  }
}
