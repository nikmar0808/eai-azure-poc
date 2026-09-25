# Goal. The same two secrets the VM path already generates
# (database-password, api-security-token), this time in a vault scoped to this window,
# with the Container Apps identity granted Key Vault Secrets User — nothing else.

data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "poc" {
  name                        = var.key_vault_name
  location                    = azurerm_resource_group.poc_aca.location
  resource_group_name         = azurerm_resource_group.poc_aca.name
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  sku_name                    = "standard"
  rbac_authorization_enabled  = true
  purge_protection_enabled    = false
  soft_delete_retention_days  = 7
}

resource "azurerm_role_assignment" "terraform_kv_officer" {
  scope                = azurerm_key_vault.poc.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id          = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "aca_kv_user" {
  scope                = azurerm_key_vault.poc.id
  role_definition_name = "Key Vault Secrets User"
  principal_id          = azurerm_user_assigned_identity.aca.principal_id
}

resource "random_password" "db_password" {
  length  = 24
  special = false
}

resource "random_password" "api_token" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "database-password"
  value        = random_password.db_password.result
  key_vault_id = azurerm_key_vault.poc.id
  depends_on   = [azurerm_role_assignment.terraform_kv_officer]
}

resource "azurerm_key_vault_secret" "api_token" {
  name         = "api-security-token"
  value        = random_password.api_token.result
  key_vault_id = azurerm_key_vault.poc.id
  depends_on   = [azurerm_role_assignment.terraform_kv_officer]
}
