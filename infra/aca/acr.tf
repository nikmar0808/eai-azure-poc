# The existing shared registry, looked up — never created here. Matches the
# same read-only reference pattern azure_infra_dev_identity.tf already uses
# for the same registry (data "azurerm_container_registry" "shared").
data "azurerm_container_registry" "shared" {
  name                = var.acr_name
  resource_group_name = var.acr_resource_group
}

# The GitHub Actions dev identity already holds AcrPush on this registry —
# that grant was created once, under /infra/shared or /infra/bootstrap's
# own state, when the three-identity bootstrap ran. It is NOT re-declared
# here: attempting to create an identical role assignment (same principal,
# same role, same scope) from a second Terraform state fails with a
# RoleAssignmentExists conflict, since Azure RBAC assignments are unique
# by that triple regardless of which Terraform state "owns" them. This
# file only adds the one grant that does not already exist: the new
# Container Apps identity's own pull access.
resource "azurerm_role_assignment" "aca_pull" {
  scope                = data.azurerm_container_registry.shared.id
  role_definition_name = "AcrPull"
  principal_id          = azurerm_user_assigned_identity.aca.principal_id
}

output "acr_id"           { value = data.azurerm_container_registry.shared.id }
output "acr_login_server" { value = data.azurerm_container_registry.shared.login_server }
