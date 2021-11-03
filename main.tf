terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "=2.81.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.6.1"
    }
    github = {
      source = "integrations/github"
      version = "4.17.0"
    }
    http = {
      source = "hashicorp/http"
      version = "2.1.0"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
      version = "1.13.0"
    }
    tls = {
      source = "hashicorp/tls"
      version = "3.1.0"
    }
  }
}

provider "azurerm" {
  features {
    log_analytics_workspace {
      permanently_delete_on_destroy = true
    }
  }
  subscription_id = var.subscription_id
}

provider "kubernetes" {
  host                   = azurerm_kubernetes_cluster.default.kube_config.0.host
  username               = azurerm_kubernetes_cluster.default.kube_config.0.username
  password               = azurerm_kubernetes_cluster.default.kube_config.0.password
  client_certificate     = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.cluster_ca_certificate)
}

provider "kubectl" {
  host                   = azurerm_kubernetes_cluster.default.kube_config.0.host
  client_certificate     = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_certificate)
  client_key             = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.client_key)
  cluster_ca_certificate = base64decode(azurerm_kubernetes_cluster.default.kube_config.0.cluster_ca_certificate)
}

provider "github" {
  # Configuration options
}

module "azure_region" {
  source  = "claranet/regions/azurerm"
  version = ">=4.2.0"

  azure_region = var.region
}

locals {
  name_prefix = "${var.environment}-${module.azure_region.location_short}-${var.application}"
  location = module.azure_region.location
}

resource "azurerm_resource_group" "default" {
  name     = "${local.name_prefix}-rg"
  location = local.location
}

resource "azurerm_log_analytics_workspace" "default" {
  name                = "${local.name_prefix}-log"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_kubernetes_cluster" "default" {
  name                = "${local.name_prefix}-aks"
  location            = azurerm_resource_group.default.location
  resource_group_name = azurerm_resource_group.default.name
  dns_prefix          = local.name_prefix
  node_resource_group = "${local.name_prefix}-internal-rg"

  default_node_pool {
    name       = "default"
    vm_size    = "Standard_D2_v2"
    node_count = 1
    enable_auto_scaling = true
    min_count = 1
    max_count = 5
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin = "azure"
  }

  role_based_access_control {
    enabled = true
  }

  addon_profile {

    oms_agent {
      enabled = true
      log_analytics_workspace_id = azurerm_log_analytics_workspace.default.id
    }
  }

  auto_scaler_profile {
    scale_down_delay_after_add = "5m"
  }

  lifecycle {
    ignore_changes = [
      default_node_pool.0.node_count
    ]
  }
}

output "az-get-credentials-command" {
  value = "az aks get-credentials -n ${local.name_prefix}-aks -g ${local.name_prefix}-rg --subscription ${var.subscription_id} --admin"
}