resource "azurerm_container_registry" "eai_acr" {
  name                = var.acr_name
  resource_group_name = azurerm_resource_group.shared.name
  location            = azurerm_resource_group.shared.location
  sku                 = "Basic"
  admin_enabled       = false
}

output "acr_id"           { value = azurerm_container_registry.eai_acr.id }
output "acr_login_server" { value = azurerm_container_registry.eai_acr.login_server }
