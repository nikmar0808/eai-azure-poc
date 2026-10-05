# Deliberately tiny: this module removes four repeated pairs of blocks, nothing more.
# Anything specific to one app (ingress, env vars, image, lifecycle) stays in apps.tf,
# next to the resource it belongs to.
locals {
  identity_block = {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }
  registry_block = {
    server   = var.acr_login_server
    identity = var.identity_id
  }
}

output "identity_block" { value = local.identity_block }
output "registry_block" { value = local.registry_block }
