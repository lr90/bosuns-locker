provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "main" {
  name     = "RG-TF"
  location = "West Europe"
}

resource "azurerm_virtual_network" "network" {
  name                = "cc_vnet"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "cc_subnet" {
  name                 = "cc-subnet"
  virtual_network_name = azurerm_virtual_network.network.name
  resource_group_name  = azurerm_resource_group.main.name
  address_prefixes     = ["10.0.0.0/24"]
}

resource "azurerm_public_ip" "cycleserver" {
  name                = "cycleserver-pip"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Dynamic"
}

resource "azurerm_network_interface" "cycleserver" {
  name                = "cycleserver-nic"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.cc_subnet.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.cycleserver.id
  }
}

resource "azurerm_linux_virtual_machine" "cycleserver" {
  name                = "cycleserver"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  size                = "Standard_D8s_v3"
  admin_username      = "csadmin"
  custom_data         = filebase64("./cc-install-base.yml")
  network_interface_ids = [
    azurerm_network_interface.cycleserver.id,
  ]

  admin_ssh_key {
    username   = "csadmin"
    public_key = file("~/.ssh/id_rsa.pub")
  }

  identity {
    type = "SystemAssigned"
  }

  os_disk {
    caching              = "ReadWrite"
    name                 = "cycleserver-os"
    storage_account_type = "StandardSSD_LRS"
  }

  source_image_reference {
    publisher = "OpenLogic"
    offer     = "CentOS"
    sku       = "7.7"
    version   = "latest"
  }
}

resource "azurerm_role_assignment" "cc_assignment" {
  scope                = azurerm_resource_group.main.id
  role_definition_name = "Contributor"
  principal_id         = lookup(azurerm_linux_virtual_machine.cycleserver.identity[0], "principal_id")
}
