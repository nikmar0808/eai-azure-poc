resource "azurerm_private_dns_zone" "postgres" {
  name                = "privatelink.postgres.database.azure.com"
  resource_group_name = azurerm_resource_group.uat.name
}
 
resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "eai-uat-vnet-link"
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = azurerm_virtual_network.uat.id
  resource_group_name   = azurerm_resource_group.uat.name
}
 
resource "azurerm_postgresql_flexible_server" "uat" {
  name                   = var.postgres_server_name
  resource_group_name    = azurerm_resource_group.uat.name
  location               = azurerm_resource_group.uat.location
  version                = "16"
  zone                   = "2"
  delegated_subnet_id    = azurerm_subnet.db.id
  private_dns_zone_id    = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false
  administrator_login    = "smart_meter_admin"
  administrator_password = random_password.postgres_admin.result
  storage_mb             = 32768
  sku_name               = "B_Standard_B1ms"
  backup_retention_days  = 7
 
  depends_on = [azurerm_subnet.db, azurerm_private_dns_zone_virtual_network_link.postgres]
}
 
resource "azurerm_postgresql_flexible_server_database" "uat" {
  name      = "smart_meter_warehouse"
  server_id = azurerm_postgresql_flexible_server.uat.id
}
 
output "postgres_fqdn" { value = azurerm_postgresql_flexible_server.uat.fqdn }
