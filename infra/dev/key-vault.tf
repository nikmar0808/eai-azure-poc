data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "dev" {
  name                       = var.key_vault_name
  location                   = azurerm_resource_group.dev.location
  resource_group_name        = azurerm_resource_group.dev.name
  tenant_id                  = var.azure_tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  purge_protection_enabled   = false
  soft_delete_retention_days = 7
}

# Grants the VM's managed identity read access to secrets in this Key
# Vault only — not Key Vault Contributor, not subscription-wide.
resource "azurerm_role_assignment" "vm_kv_secrets_user" {
  scope                = azurerm_key_vault.dev.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.vm.principal_id
}

# The identity applying this Terraform also needs read/write on secrets,
# to create the two below.
resource "azurerm_role_assignment" "terraform_kv_secrets_officer" {
  scope                = azurerm_key_vault.dev.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "random_password" "postgres_admin" {
  length  = 24
  special = false
}

resource "random_password" "api_security_token" {
  length  = 32
  special = false
}

resource "azurerm_key_vault_secret" "database_password" {
  name         = "database-password"
  value        = random_password.postgres_admin.result
  key_vault_id = azurerm_key_vault.dev.id
  depends_on   = [azurerm_role_assignment.terraform_kv_secrets_officer]
}

resource "azurerm_key_vault_secret" "api_security_token" {
  name         = "api-security-token"
  value        = random_password.api_security_token.result
  key_vault_id = azurerm_key_vault.dev.id
  depends_on   = [azurerm_role_assignment.terraform_kv_secrets_officer]
}
