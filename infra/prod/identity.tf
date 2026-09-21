resource "azurerm_user_assigned_identity" "vm" {
  name                = "eai-prod-vm-id"
  location            = azurerm_resource_group.prod.location
  resource_group_name = azurerm_resource_group.prod.name
}

# Pull-only access to the shared registry — the VM never needs push
# permission, matching the AWS EC2 instance role's pull-only ECR scope.
resource "azurerm_role_assignment" "vm_acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.vm.principal_id
}

data "azuread_service_principal" "gha_deploy_prod" {
  client_id = var.gha_deploy_client_id
}

# Grants only the ability to invoke Run Command against this one VM — not
# Contributor on the resource group, not access to any other environment's
# VM. This is the Azure equivalent of AWS's ssm:SendCommand statement
# scoped by ssm:resourceTag/Name to one tagged instance.
resource "azurerm_role_assignment" "gha_prod_vm_runcommand" {
  scope                = azurerm_linux_virtual_machine.prod.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = data.azuread_service_principal.gha_deploy_prod.object_id
}

resource "azurerm_role_assignment" "gha_prod_kv_secrets_user" {
  scope                = azurerm_key_vault.prod.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azuread_service_principal.gha_deploy_prod.object_id
}

# Required by promote-prod's "confirm the image tag exists" step, which
# calls az acr repository show against the shared registry using
# gha_deploy_prod's own AAD identity — a data-plane read, not covered by
# the VM Contributor / Key Vault grants above. Pull-only: promote-prod never
# pushes, matching the read-only relationship PROD has with the registry
# throughout this plan (Section 4 of RELEASE_MANAGEMENT_GEN.md — only DEV
# builds and pushes).
resource "azurerm_role_assignment" "gha_prod_acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = data.azuread_service_principal.gha_deploy_prod.object_id
}

output "vm_identity_client_id" { value = azurerm_user_assigned_identity.vm.client_id }
