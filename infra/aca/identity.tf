resource "azurerm_user_assigned_identity" "aca" {
  name                = "poc-eai-aca-id"
  location            = azurerm_resource_group.poc_aca.location
  resource_group_name = azurerm_resource_group.poc_aca.name
}

# The GitHub Actions deployment identity bootstrapped in task 7.9. Looked up
# by client ID rather than recreated — the same principle as the existing
# azure_infra_dev_identity.tf pattern: RBAC is granted where the resource
# exists, not where the identity was created. This is deliberately the
# DEV identity, not a new one and not UAT/PROD: in the original three-role
# model, only dev's identity is granted AcrPush on the shared registry
# (azure_infra_dev_identity.tf's gha_dev_acr_push resource) — UAT and PROD
# hold AcrPull only, since they never build, only promote an already-built
# tag. This phase builds new images, so it needs the one identity that can
# push. The value is the same GUID already sitting in the GitHub repository
# variable AZURE_CLIENT_ID_DEV — nothing new is derived or recorded here.
data "azuread_service_principal" "gha_deploy" {
  client_id = var.gha_deploy_client_id
}

output "aca_identity_client_id"     { value = azurerm_user_assigned_identity.aca.client_id }
output "aca_identity_principal_id"  { value = azurerm_user_assigned_identity.aca.principal_id }
