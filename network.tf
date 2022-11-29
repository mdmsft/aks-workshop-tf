resource "azurerm_virtual_network" "main" {
  name                = "vnet-${local.resource_suffix}"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  address_space       = [var.address_space]

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_subnet" "cluster" {
  name                 = "snet-aks"
  virtual_network_name = azurerm_virtual_network.main.name
  resource_group_name  = azurerm_resource_group.main.name
  address_prefixes     = [cidrsubnet(var.address_space, 0, 0)]
}

resource "azurerm_public_ip_prefix" "cluster" {
  name                = "ippre-${local.resource_suffix}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  prefix_length       = var.nat_gateway_public_ip_prefix_length
  sku                 = "Standard"
  zones               = ["1", "2", "3"]

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_nat_gateway" "cluster" {
  name                    = "ng-${local.resource_suffix}-aks"
  location                = azurerm_resource_group.main.location
  resource_group_name     = azurerm_resource_group.main.name
  idle_timeout_in_minutes = 4
  sku_name                = "Standard"

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_nat_gateway_public_ip_prefix_association" "cluster" {
  nat_gateway_id      = azurerm_nat_gateway.cluster.id
  public_ip_prefix_id = azurerm_public_ip_prefix.cluster.id
}

resource "azurerm_subnet_nat_gateway_association" "cluster" {
  nat_gateway_id = azurerm_nat_gateway.cluster.id
  subnet_id      = azurerm_subnet.cluster.id
}

resource "azurerm_public_ip" "nginx" {
  name                = "pip-${local.resource_suffix}-nginx"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
}
