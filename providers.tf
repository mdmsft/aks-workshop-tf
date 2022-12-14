terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~>3.0"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~>2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~>3.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~>2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~>2.0"
    }
  }
  backend "azurerm" {
    container_name = "tfstate"
  }
}

provider "azurerm" {
  client_id       = var.client_id
  client_secret   = var.client_secret
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id

  features {
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}

# provider "azurerm" {
#   alias           = "log_analytics_workspace"
#   client_id       = var.client_id
#   client_secret   = var.client_secret
#   subscription_id = var.subscription_id
#   tenant_id       = var.tenant_id
# }

provider "azuread" {
  client_id     = var.client_id
  client_secret = var.client_secret
  tenant_id     = var.tenant_id
}

provider "helm" {
  kubernetes {
    config_path = ".kube/config"
  }
}

provider "kubernetes" {
  config_path = ".kube/config"
}
