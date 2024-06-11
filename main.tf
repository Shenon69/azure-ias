terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.106.1"
    }
  }
}

provider "azurerm" {
  subscription_id = "4eb29f76-86f1-42cb-9822-2de9395f3625"
  client_id       = "7d4e9a40-f4b3-4b0a-9265-5e66bd8b7cc7"
  client_secret   = "Tvy8Q~PLGvaOt9td2P6xjt6NU.BCX7aaGjAAydg-"
  tenant_id       = "84c31ca0-ac3b-4eae-ad11-519d80233e6f"
  features {}
}

locals {
  resource_group_name = "azure-ias-rg"
  location            = "East US"
}

resource "azurerm_resource_group" "azure-ias-rg" {
  name     = local.resource_group_name
  location = local.location
}

resource "azurerm_virtual_network" "azure-ias-vnet" {
  name                = "ias-vnet"
  location            = local.location
  resource_group_name = local.resource_group_name
  address_space       = ["10.0.0.0/16"]

  depends_on = [
    local.resource_group_name
  ]

}

resource "azurerm_subnet" "subnetA" {
  name                 = "subnetA"
  resource_group_name  = local.resource_group_name
  virtual_network_name = azurerm_virtual_network.azure-ias-vnet.name
  address_prefixes     = ["10.0.1.0/24"]

  depends_on = [
    azurerm_virtual_network.azure-ias-vnet
  ]
}

resource "azurerm_network_interface" "ias-nic" {
  name                = "ias-nic"
  location            = local.location
  resource_group_name = local.resource_group_name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.subnetA.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.ias-public-ip.id
  }

  depends_on = [
    azurerm_virtual_network.azure-ias-vnet,
    azurerm_public_ip.ias-public-ip,
    azurerm_subnet.subnetA
  ]
}

resource "azurerm_windows_virtual_machine" "ias-vm" {
  name                = "ias-vm"
  resource_group_name = local.resource_group_name
  location            = local.location
  size                = "Standard_D2s_v3"
  admin_username      = "demouser"
  admin_password      = "Azure@123"
  availability_set_id = azurerm_availability_set.ias-aset.id
  network_interface_ids = [
    azurerm_network_interface.ias-nic.id
  ]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2019-Datacenter"
    version   = "latest"
  }

  depends_on = [
    azurerm_network_interface.ias-nic,
    azurerm_availability_set.ias-aset
  ]
}

resource "azurerm_public_ip" "ias-public-ip" {
  name                = "ias-public-ip"
  resource_group_name = local.resource_group_name
  location            = local.location
  allocation_method   = "Static"
}

resource "azurerm_managed_disk" "azure-ias-disk" {
  name                 = "ias-vm-disk1"
  location             = local.location
  resource_group_name  = local.resource_group_name
  storage_account_type = "Standard_LRS"
  create_option        = "Empty"
  disk_size_gb         = 16
}

resource "azurerm_virtual_machine_data_disk_attachment" "ias-vm-disk1" {
  managed_disk_id    = azurerm_managed_disk.azure-ias-disk.id
  virtual_machine_id = azurerm_windows_virtual_machine.ias-vm.id
  lun                = "0"
  caching            = "ReadWrite"

  depends_on = [
    azurerm_windows_virtual_machine.ias-vm,
    azurerm_managed_disk.azure-ias-disk
  ]
}

resource "azurerm_availability_set" "ias-aset" {
  name                         = "ias-aset"
  location                     = local.location
  resource_group_name          = local.resource_group_name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2

  depends_on = [
    local.resource_group_name
  ]

}

resource "azurerm_storage_account" "ias-storage-account" {
  name                            = "iasstorraccount"
  resource_group_name             = local.resource_group_name
  location                        = local.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = true
}

resource "azurerm_storage_container" "ias-storage-container" {
  name                  = "iasstoragecontainer"
  storage_account_name  = azurerm_storage_account.ias-storage-account.name
  container_access_type = "private"

  depends_on = [
    azurerm_storage_account.ias-storage-account
  ]
}

resource "azurerm_storage_blob" "IIS-config" {
  name                   = "IIS-config.ps1"
  storage_account_name   = azurerm_storage_account.ias-storage-account.name
  storage_container_name = azurerm_storage_container.ias-storage-container.name
  type                   = "Block"
  source                 = "IIS_config.ps1"

  depends_on = [
    azurerm_storage_container.ias-storage-container
  ]
}

resource "azurerm_virtual_machine_extension" "azure-ias-vm-ext" {
  name                 = "IIS-config"
  virtual_machine_id   = azurerm_windows_virtual_machine.ias-vm.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"

  settings = <<SETTINGS
 {
  "fileUris": ["https://iasstorraccount.blob.core.windows.net/iasstoragecontainer/IIS-config.ps1?sp=rw&st=2024-06-03T13:48:02Z&se=2024-06-03T21:48:02Z&sv=2022-11-02&sr=b&sig=sd07WedPR7c%2BMomz6X2ekXLcP1p2JwNjtI%2FeJFs7ohk%3D"],
  "commandToExecute": "powershell -ExecutionPolicy Unrestricted -file IIS-config.ps1"
 }
SETTINGS

  depends_on = [
    azurerm_storage_account.ias-storage-account,
    azurerm_storage_blob.IIS-config
  ]

}

resource "azurerm_network_security_group" "ias-nsg" {
  name                = "ias-nsg"
  location            = local.location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "inbound80"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nsg-association" {
  subnet_id                 = azurerm_subnet.subnetA.id
  network_security_group_id = azurerm_network_security_group.ias-nsg.id

  depends_on = [
    azurerm_network_security_group.ias-nsg
  ]
}












