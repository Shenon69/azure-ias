resource "azurerm_storage_account" "ias-storage-account" {
  name                            = "${var.app_name}storeacc"
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  allow_nested_items_to_be_public = true

  depends_on = [
    var.resource_group_name
  ]
}

resource "azurerm_storage_container" "ias-storage-container" {
 name                  = "${var.app_name}blogcontainer"
  storage_account_name  = azurerm_storage_account.ias-storage-account.name
  container_access_type = "blob"

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

