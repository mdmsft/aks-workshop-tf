locals {
  kubernetes_cluster_orchestrator_version                   = var.kubernetes_cluster_orchestrator_version == null ? data.azurerm_kubernetes_service_versions.main.latest_version : var.kubernetes_cluster_orchestrator_version
  kubernetes_cluster_default_node_pool_orchestrator_version = var.kubernetes_cluster_default_node_pool_orchestrator_version == null ? local.kubernetes_cluster_orchestrator_version : var.kubernetes_cluster_default_node_pool_orchestrator_version
  kubernetes_cluster_node_pool_orchestrator_version         = { for k, v in var.kubernetes_cluster_node_pools : k => v.orchestrator_version == null ? local.kubernetes_cluster_orchestrator_version : v.orchestrator_version }
  tls_secret_name                                           = "wildcard"
  tls_secret_namespace                                      = "ingress-nginx"
  kubeconfig_path                                           = ".kube/config"
}

resource "azurerm_kubernetes_cluster" "main" {
  name                              = "aks-${local.global_resource_suffix}"
  location                          = azurerm_resource_group.main.location
  resource_group_name               = azurerm_resource_group.main.name
  dns_prefix                        = local.global_resource_suffix
  automatic_channel_upgrade         = var.kubernetes_cluster_automatic_channel_upgrade
  role_based_access_control_enabled = true
  azure_policy_enabled              = var.kubernetes_cluster_azure_policy_enabled
  open_service_mesh_enabled         = var.kubernetes_cluster_open_service_mesh_enabled
  kubernetes_version                = local.kubernetes_cluster_orchestrator_version
  oidc_issuer_enabled               = var.kubernetes_cluster_oidc_issuer_enabled
  node_resource_group               = "rg-${local.resource_suffix}-aks"
  sku_tier                          = var.kubernetes_cluster_sku_tier
  workload_identity_enabled         = var.kubernetes_cluster_oidc_issuer_enabled && var.kubernetes_cluster_workload_identity_enabled

  service_principal {
    client_id     = var.kubernetes_cluster_client_id
    client_secret = var.kubernetes_cluster_client_secret
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.kubernetes_cluster_default_node_pool_vm_size
    enable_auto_scaling          = true
    min_count                    = var.kubernetes_cluster_default_node_pool_min_count
    max_count                    = var.kubernetes_cluster_default_node_pool_max_count
    max_pods                     = var.kubernetes_cluster_default_node_pool_max_pods
    os_disk_size_gb              = var.kubernetes_cluster_default_node_pool_os_disk_size_gb
    os_disk_type                 = var.kubernetes_cluster_default_node_pool_os_disk_type
    os_sku                       = var.kubernetes_cluster_default_node_pool_os_sku
    orchestrator_version         = local.kubernetes_cluster_default_node_pool_orchestrator_version
    only_critical_addons_enabled = true
    vnet_subnet_id               = azurerm_subnet.cluster.id
    zones                        = var.kubernetes_cluster_default_node_pool_availability_zones

    upgrade_settings {
      max_surge = var.kubernetes_cluster_default_node_pool_max_surge
    }
  }

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  network_profile {
    network_plugin     = var.kubernetes_cluster_network_plugin
    network_policy     = var.kubernetes_cluster_network_policy
    dns_service_ip     = cidrhost(var.kubernetes_cluster_service_cidr, 10)
    docker_bridge_cidr = var.kubernetes_cluster_docker_bridge_cidr
    service_cidr       = var.kubernetes_cluster_service_cidr
    load_balancer_sku  = "standard"
    outbound_type      = "userAssignedNATGateway"
  }

  dynamic "key_vault_secrets_provider" {
    for_each = var.kubernetes_cluster_key_vault_secrets_provider_enabled ? [{}] : []
    content {
      secret_rotation_enabled  = true
      secret_rotation_interval = "1m"
    }
  }

  dynamic "microsoft_defender" {
    for_each = var.kubernetes_cluster_microsoft_defender_enabled ? [{}] : []
    content {
      log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
    }
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "main" {
  for_each              = var.kubernetes_cluster_node_pools
  name                  = each.key
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = each.value.vm_size
  enable_auto_scaling   = true
  min_count             = each.value.min_count
  max_count             = each.value.max_count
  max_pods              = each.value.max_pods
  os_disk_size_gb       = each.value.os_disk_size_gb
  os_disk_type          = each.value.os_disk_type
  os_sku                = each.value.os_sku
  os_type               = each.value.os_type
  orchestrator_version  = local.kubernetes_cluster_node_pool_orchestrator_version[each.key]
  vnet_subnet_id        = azurerm_subnet.cluster.id
  zones                 = each.value.zones
  node_labels           = each.value.node_labels
  node_taints           = each.value.node_taints

  upgrade_settings {
    max_surge = each.value.max_surge
  }

  lifecycle {
    ignore_changes = [
      tags
    ]
  }
}

resource "local_file" "kube_config" {
  filename = local.kubeconfig_path
  content  = azurerm_kubernetes_cluster.main.kube_config_raw
}

resource "azurerm_resource_policy_assignment" "cluster_allowed_registry" {
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/febd0533-8e55-448f-b837-bd0e06f16469"
  name                 = "Allow only one registry"
  resource_id          = azurerm_kubernetes_cluster.main.id
  parameters           = <<EOF
    {
      "allowedContainerImagesRegex": {
        "value": "^${azurerm_container_registry.main.login_server}\\/.+$"
      }
    }
  EOF
}

resource "helm_release" "nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  cleanup_on_fail  = true
  atomic           = true
  wait             = true

  values = [
    templatefile("./k8s/nginx.values.yaml",
      {
        load_balancer_ip_address             = azurerm_public_ip.nginx.ip_address,
        load_balancer_ip_resource_group_name = azurerm_resource_group.main.name,
        tls_secret_namespace                 = local.tls_secret_namespace
        tls_secret_name                      = local.tls_secret_name
    })
  ]

  depends_on = [
    local_file.kube_config,
    azurerm_public_ip.nginx,
  ]
}

resource "kubernetes_secret_v1" "nginx" {
  metadata {
    name      = local.tls_secret_name
    namespace = local.tls_secret_namespace
  }

  data = {
    "tls.crt" = file(var.tls_certificate_path)
    "tls.key" = file(var.tls_key_path)
  }

  type = "kubernetes.io/tls"

  depends_on = [
    helm_release.nginx
  ]
}

resource "kubernetes_secret_v1" "docker" {
  metadata {
    name = "docker"
  }

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "${azurerm_container_registry.main.login_server}" = {
          username = azurerm_container_registry.main.admin_username,
          password = azurerm_container_registry.main.admin_password,
          email    = "admin@contoso.com"
        }
      }
    })
  }

  type = "kubernetes.io/dockerconfigjson"

  depends_on = [
    helm_release.nginx
  ]
}
