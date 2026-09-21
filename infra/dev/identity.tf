resource "azurerm_user_assigned_identity" "vm" {
  name                = "eai-dev-vm-id"
  location            = azurerm_resource_group.dev.location
  resource_group_name = azurerm_resource_group.dev.name
}

# Pull-only access to the shared registry — the VM never needs push
# permission, matching the AWS EC2 instance role's pull-only ECR scope.
resource "azurerm_role_assignment" "vm_acr_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.vm.principal_id
}

data "azuread_service_principal" "gha_deploy_dev" {
  client_id = var.gha_deploy_client_id
}

# Only DEV builds and pushes images — the GitHub Actions workflow is configured to fail
# if it tries to push to ACR from those environments.
###########################################################################
#                                                                         #
# This resource is not configured for UAT or PROD because                 #
# those environments' builds are read-only and do not push images to ACR. #
#                                                                         #
###########################################################################
resource "azurerm_role_assignment" "gha_dev_acr_push" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPush"
  principal_id         = data.azuread_service_principal.gha_deploy_dev.object_id
}

# Grants only the ability to invoke Run Command against this one VM — not
# Contributor on the resource group, not access to any other environment's
# VM. This is the Azure equivalent of AWS's ssm:SendCommand statement
# scoped by ssm:resourceTag/Name to one tagged instance.
resource "azurerm_role_assignment" "gha_dev_vm_runcommand" {
  scope                = azurerm_linux_virtual_machine.dev.id
  role_definition_name = "Virtual Machine Contributor"
  principal_id         = data.azuread_service_principal.gha_deploy_dev.object_id
}

# Required by the deploy-dev job in ci.yml, which reads the two Key
# Vault secrets from within the GitHub Actions runner rather than on the VM.
resource "azurerm_role_assignment" "gha_dev_kv_secrets_user" {
  scope                = azurerm_key_vault.dev.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = data.azuread_service_principal.gha_deploy_dev.object_id
}

output "vm_identity_client_id" { value = azurerm_user_assigned_identity.vm.client_id }
