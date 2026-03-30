###############################################################################
# Kubernetes Module - Azure (AKS)
# Creates an AKS cluster with system, application, and data node pools
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

locals {
  cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}-aks"
  dns_prefix   = var.dns_prefix != "" ? var.dns_prefix : "${var.project_name}-${var.environment}"

  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
    module      = "kubernetes"
  })

  # Default node pools for PipesHub workloads
  default_node_pools = {
    app = {
      vm_size         = "Standard_D8s_v3"
      min_count       = 1
      max_count       = 3
      node_count      = 1
      os_disk_size_gb = 128
      max_pods        = 110
      node_labels = {
        "pipeshub.com/node-type" = "application"
      }
      node_taints    = []
      priority       = var.environment == "dev" ? "Spot" : "Regular"
      spot_max_price = var.environment == "dev" ? -1 : -1
      zones          = var.environment == "prod" ? ["1", "2", "3"] : []
    }
    data = {
      vm_size         = "Standard_E4s_v3"
      min_count       = 1
      max_count       = 2
      node_count      = 1
      os_disk_size_gb = 256
      max_pods        = 60
      node_labels = {
        "pipeshub.com/node-type" = "data"
      }
      node_taints    = ["pipeshub.com/data-only=true:NoSchedule"]
      priority       = "Regular"
      spot_max_price = -1
      zones          = var.environment == "prod" ? ["1", "2", "3"] : []
    }
  }

  # Merge user-provided node pools with defaults (user overrides win)
  node_pools = merge(local.default_node_pools, var.node_pools)
}

# -----------------------------------------------------------------------------
# AKS Cluster
# -----------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster" "this" {
  name                = local.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = local.dns_prefix
  kubernetes_version  = var.kubernetes_version

  tags = local.common_tags

  # System node pool (required, runs kube-system workloads)
  default_node_pool {
    name                 = "system"
    vm_size              = var.system_node_pool_vm_size
    auto_scaling_enabled = true
    min_count            = var.system_node_pool_min_count
    max_count            = var.system_node_pool_max_count
    os_disk_size_gb      = 128
    max_pods             = 110
    vnet_subnet_id       = var.vnet_subnet_id
    zones                = var.environment == "prod" ? ["1", "2", "3"] : []

    node_labels = {
      "pipeshub.com/node-type" = "system"
    }

    upgrade_settings {
      max_surge = "10%"
    }
  }

  # Identity: system-assigned managed identity
  identity {
    type = "SystemAssigned"
  }

  # Azure CNI networking
  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure"
    service_cidr      = "172.16.0.0/16"
    dns_service_ip    = "172.16.0.10"
    load_balancer_sku = "standard"

    load_balancer_profile {
      managed_outbound_ip_count = var.environment == "prod" ? 2 : 1
    }
  }

  # Azure AD RBAC integration
  azure_active_directory_role_based_access_control {
    azure_rbac_enabled     = true
    admin_group_object_ids = var.azure_ad_admin_group_object_ids
  }

  # Workload Identity for pod-level Azure AD authentication
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Storage CSI drivers
  storage_profile {
    disk_driver_enabled = true
    file_driver_enabled = true
    blob_driver_enabled = false
  }

  # Autoscaler profile
  auto_scaler_profile {
    balance_similar_node_groups      = true
    max_graceful_termination_sec     = "600"
    scale_down_delay_after_add       = "10m"
    scale_down_delay_after_delete    = "10s"
    scale_down_unneeded              = "10m"
    scale_down_utilization_threshold = "0.5"
    skip_nodes_with_local_storage    = false
    skip_nodes_with_system_pods      = true
  }

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count,
      kubernetes_version,
    ]
  }
}

# -----------------------------------------------------------------------------
# Additional Node Pools (application, data, or custom)
# -----------------------------------------------------------------------------

resource "azurerm_kubernetes_cluster_node_pool" "this" {
  for_each = local.node_pools

  name                  = substr(each.key, 0, 12)
  kubernetes_cluster_id = azurerm_kubernetes_cluster.this.id
  vm_size               = each.value.vm_size
  auto_scaling_enabled  = true
  min_count             = each.value.min_count
  max_count             = each.value.max_count
  node_count            = each.value.node_count
  os_disk_size_gb       = each.value.os_disk_size_gb
  max_pods              = each.value.max_pods
  vnet_subnet_id        = var.vnet_subnet_id
  node_labels           = each.value.node_labels
  node_taints           = each.value.node_taints
  priority              = each.value.priority
  spot_max_price        = each.value.priority == "Spot" ? each.value.spot_max_price : null
  eviction_policy       = each.value.priority == "Spot" ? "Delete" : null
  zones                 = each.value.zones

  upgrade_settings {
    max_surge = "10%"
  }

  tags = local.common_tags

  lifecycle {
    ignore_changes = [
      node_count,
    ]
  }
}
