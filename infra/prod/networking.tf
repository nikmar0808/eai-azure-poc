resource "azurerm_virtual_network" "prod" {
  name                = "eai-prod-vnet"
  address_space       = ["10.10.0.0/16"]
  location            = azurerm_resource_group.prod.location
  resource_group_name = azurerm_resource_group.prod.name
}

resource "azurerm_subnet" "app" {
  name                 = "app-subnet"
  resource_group_name  = azurerm_resource_group.prod.name
  virtual_network_name = azurerm_virtual_network.prod.name
  address_prefixes     = ["10.10.1.0/24"]
}

resource "azurerm_subnet" "db" {
  name                 = "db-subnet"
  resource_group_name  = azurerm_resource_group.prod.name
  virtual_network_name = azurerm_virtual_network.prod.name
  address_prefixes     = ["10.10.2.0/24"]

  delegation {
    name = "postgres-delegation"
    service_delegation {
      name    = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# --- SUPERSEDED: Azure Bastion subnet ---
# This is how interactive VM access should have been implemented if not for
# Azure Free Tier's 3-Standard-public-IP-per-subscription limit. A dedicated
# Bastion host per environment (ARCHITECTURE_AZURE.md, Section 6) requires one additional
# Standard public IP per environment (3 total across DEV/UAT/PROD), which
# together with the 3 VM public IPs already required as APIM's HTTP_PROXY
# backend target (ARCHITECTURE_AZURE.md, Section 3) exceeds the free-tier quota (6 > 3, and
# the VM IPs are non-negotiable). Commented out below and replaced by the
# AllowOperatorSSH rule on the app NSG plus `az ssh vm` (ARCHITECTURE_AZURE.md, Section 6),
# which reuses the VM's already-required public IP and consumes no
# additional quota. A real, non-free-tier subscription should re-enable
# this subnet and the Bastion resources in bastion.tf, and remove the
# AllowOperatorSSH rule below and its NSG-based replacement in favor of
# this platform-managed, non-internet-routable path.
#
# Azure Bastion requires a subnet with exactly this name — not a naming
# convention, a hard platform requirement.
# resource "azurerm_subnet" "bastion" {
#   name                 = "AzureBastionSubnet"
#   resource_group_name  = azurerm_resource_group.prod.name
#   virtual_network_name = azurerm_virtual_network.prod.name
#   address_prefixes     = ["10.10.3.0/26"]
# }

resource "azurerm_network_security_group" "app" {
  name                = "eai-prod-app-nsg"
  location            = azurerm_resource_group.prod.location
  resource_group_name = azurerm_resource_group.prod.name

  security_rule {
    name                       = "AllowJavaGateway"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "8081"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Replaces Bastion's network path (see superseded subnet block above) —
  # direct AAD-authenticated SSH to the VM's own public IP, which is already
  # required for the APIM backend target and therefore consumes no
  # additional public-IP quota. var.operator_ip_cidr must be a narrow range
  # (ideally a /32) — never 0.0.0.0/0, since unlike Bastion's data path this
  # port is genuinely internet-facing.
  security_rule {
    name                       = "AllowOperatorSSH"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = var.operator_ip_cidr
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "app" {
  subnet_id                 = azurerm_subnet.app.id
  network_security_group_id = azurerm_network_security_group.app.id
}

resource "azurerm_public_ip" "vm" {
  name                = "eai-prod-host-pip"
  location            = azurerm_resource_group.prod.location
  resource_group_name = azurerm_resource_group.prod.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "vm" {
  name                = "eai-prod-host-nic"
  location            = azurerm_resource_group.prod.location
  resource_group_name = azurerm_resource_group.prod.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.app.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.vm.id
  }
}
