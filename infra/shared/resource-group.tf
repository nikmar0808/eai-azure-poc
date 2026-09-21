resource "azurerm_resource_group" "shared" {
  name     = "eai-shared-rg"
  location = "centralindia"
  tags     = { Project = "eai-project", ManagedBy = "terraform", Scope = "shared" }
}
