resource "azurerm_container_registry" "main" {
  name                   = "cr${local.project}${local.environment}${var.region}"
  location               = azurerm_resource_group.main.location
  resource_group_name    = azurerm_resource_group.main.name
  sku                    = var.container_registry_sku
  admin_enabled          = true
  anonymous_pull_enabled = false

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}
