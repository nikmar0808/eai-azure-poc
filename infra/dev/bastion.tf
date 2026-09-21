# resource "azurerm_public_ip" "bastion" {
#   name                = "eai-dev-bastion-pip"
#   location            = azurerm_resource_group.dev.location
#   resource_group_name = azurerm_resource_group.dev.name
#   allocation_method   = "Static"
#   sku                 = "Standard"
# }
#
# resource "azurerm_bastion_host" "dev" {
#   name                = "eai-dev-bastion"
#   location            = azurerm_resource_group.dev.location
#   resource_group_name = azurerm_resource_group.dev.name
#   sku                 = "Standard"  # Standard SKU is required for native-client/Azure AD login support
#   tunneling_enabled   = true        # Required for `az network bastion ssh` (native client). Without
#                                      # this, the az CLI's bastion extension fails with
#                                      # KeyError: 'enableTunneling' when the SSH extension tries to
#                                      # read this setting from the Bastion resource.
#
#   ip_configuration {
#     name                 = "configuration"
#     subnet_id            = azurerm_subnet.bastion.id
#     public_ip_address_id = azurerm_public_ip.bastion.id
#   }
# }
