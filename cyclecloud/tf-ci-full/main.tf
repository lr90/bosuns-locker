provider "azurerm" {
  features {}
}

data "azurerm_subscription" "current" {
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

resource "azurerm_storage_account" "storage" {
  name                     = var.cyclecloud_storage_account
  resource_group_name      = azurerm_resource_group.main.name
  location                 = azurerm_resource_group.main.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
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
  custom_data         = base64encode( <<CUSTOM_DATA
#cloud-config
#
# installs CycleCloud on the VM
#

yum_repos:
  azure-cli:
    baseurl: https://packages.microsoft.com/yumrepos/azure-cli
    enabled: true
    gpgcheck: true
    gpgkey: https://packages.microsoft.com/keys/microsoft.asc
    name: Azure CLI
  cyclecloud:
    baseurl: https://packages.microsoft.com/yumrepos/cyclecloud
    enabled: true
    gpgcheck: true
    gpgkey: https://packages.microsoft.com/keys/microsoft.asc
    name: Cycle Cloud

packages:
- java-1.8.0-openjdk-headless
- azure-cli
- cyclecloud8

write_files:
- content: |
    [{
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.initial_user",
        "Value": "ccadmin"
    },
    {
        "AdType": "Application.Setting",
        "Name": "cycleserver.installation.complete",
        "Value": true
    },
    {
        "AdType": "AuthenticatedUser",
        "Name": "ccadmin",
        "RawPassword": "${var.cyclecloud_password}",
        "Superuser": true
    }] 
  owner: root:root
  path: ./account_data.json
  permissions: '0644'
- content: |
    {
      "Name": "Azure",
      "Environment": "public",
      "AzureRMSubscriptionId": "${data.azurerm_subscription.current.subscription_id}",
      "AzureRMUseManagedIdentity": true,
      "Location": "westeurope",
      "RMStorageAccount": "${var.cyclecloud_storage_account}",
      "RMStorageContainer": "cyclecloud"
    }
  owner: root:root
  path: ./azure_data.json
  permissions: '0644'

runcmd:
- sed -i --follow-symlinks "s/webServerPort=.*/webServerPort=80/g" /opt/cycle_server/config/cycle_server.properties
- sed -i --follow-symlinks "s/webServerSslPort=.*/webServerSslPort=443/g" /opt/cycle_server/config/cycle_server.properties
- sed -i --follow-symlinks "s/webServerEnableHttps=.*/webServerEnableHttps=true/g" /opt/cycle_server/config/cycle_server.properties
- systemctl restart cycle_server
- mv ./account_data.json /opt/cycle_server/config/data/
- sleep 5
- /opt/cycle_server/cycle_server execute "update Application.Setting set Value = false where name == \"authorization.check_datastore_permissions\""
- unzip /opt/cycle_server/tools/cyclecloud-cli
- ./cyclecloud-cli-installer/install.sh --system
- sleep 60
- /usr/local/bin/cyclecloud initialize --batch --url=https://localhost --verify-ssl=false --username="ccadmin" --password="${var.cyclecloud_password}"
- /usr/local/bin/cyclecloud account create -f ./azure_data.json
  CUSTOM_DATA
  )
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
