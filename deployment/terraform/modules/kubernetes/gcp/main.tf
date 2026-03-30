###############################################################################
# Kubernetes Module - GCP
# Creates a GKE Standard cluster with configurable node pools, Workload
# Identity, network policy, shielded nodes, and Cloud Operations integration
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

locals {
  cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}-gke"

  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_name
  })
}

# -----------------------------------------------------------------------------
# GKE Cluster
# Standard mode with Workload Identity, VPC-native networking, and private nodes
# -----------------------------------------------------------------------------

resource "google_container_cluster" "primary" {
  project  = var.project_id
  name     = local.cluster_name
  location = var.region

  # Use REGULAR release channel for balanced stability and feature availability
  release_channel {
    channel = "REGULAR"
  }

  min_master_version = var.kubernetes_version != "" ? var.kubernetes_version : null

  # Remove the default node pool after creation; we manage our own pools
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network_id
  subnetwork = var.subnet_id

  # VPC-native cluster using secondary ranges from the networking module
  ip_allocation_policy {
    cluster_secondary_range_name  = var.pod_secondary_range_name
    services_secondary_range_name = var.service_secondary_range_name
  }

  # Private cluster: nodes have no external IPs, master accessible via authorized networks
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Authorize specific networks to access the Kubernetes API server
  dynamic "master_authorized_networks_config" {
    for_each = length(var.master_authorized_networks) > 0 ? [1] : []
    content {
      dynamic "cidr_blocks" {
        for_each = var.master_authorized_networks
        content {
          cidr_block   = cidr_blocks.value.cidr_block
          display_name = cidr_blocks.value.display_name
        }
      }
    }
  }

  # Enable Workload Identity for secure GCP service access from pods
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable network policy enforcement via Calico
  network_policy {
    enabled  = true
    provider = "CALICO"
  }

  # Enable NetworkPolicy controller add-on
  addons_config {
    network_policy_config {
      disabled = false
    }

    http_load_balancing {
      disabled = false
    }

    horizontal_pod_autoscaling {
      disabled = false
    }

    gce_persistent_disk_csi_driver_config {
      enabled = true
    }
  }

  # Binary authorization for container image verification
  binary_authorization {
    evaluation_mode = var.environment == "prod" ? "PROJECT_SINGLETON_POLICY_ENFORCE" : "DISABLED"
  }

  # Cloud Operations (logging and monitoring)
  logging_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "WORKLOADS",
    ]
  }

  monitoring_config {
    enable_components = [
      "SYSTEM_COMPONENTS",
      "STORAGE",
      "POD",
      "DEPLOYMENT",
      "STATEFULSET",
    ]

    managed_prometheus {
      enabled = true
    }
  }

  # Security: enable shielded nodes cluster-wide
  node_config {
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }
  }

  resource_labels = local.common_labels

  # Prevent accidental cluster deletion in production
  deletion_protection = var.environment == "prod" ? true : false

  lifecycle {
    ignore_changes = [
      node_config,
      initial_node_count,
    ]
  }
}

# -----------------------------------------------------------------------------
# Node Pools
# Dynamic creation based on the node_pools variable map
# Each pool gets its own service account for least-privilege access
# -----------------------------------------------------------------------------

resource "google_service_account" "node_pool" {
  for_each = var.node_pools

  project      = var.project_id
  account_id   = "${local.cluster_name}-${each.key}"
  display_name = "GKE node pool service account for ${each.key}"
}

resource "google_project_iam_member" "node_pool_log_writer" {
  for_each = var.node_pools

  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node_pool[each.key].email}"
}

resource "google_project_iam_member" "node_pool_metric_writer" {
  for_each = var.node_pools

  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node_pool[each.key].email}"
}

resource "google_project_iam_member" "node_pool_monitoring_viewer" {
  for_each = var.node_pools

  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node_pool[each.key].email}"
}

resource "google_project_iam_member" "node_pool_artifact_reader" {
  for_each = var.node_pools

  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.node_pool[each.key].email}"
}

resource "google_container_node_pool" "pools" {
  for_each = var.node_pools

  project  = var.project_id
  name     = "${local.cluster_name}-${each.key}"
  location = var.region
  cluster  = google_container_cluster.primary.name

  autoscaling {
    min_node_count = each.value.min_count
    max_node_count = each.value.max_count
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }

  upgrade_settings {
    max_surge       = 1
    max_unavailable = 0
    strategy        = "SURGE"
  }

  node_config {
    machine_type = each.value.machine_type
    disk_size_gb = each.value.disk_size_gb
    disk_type    = each.value.disk_type
    spot         = each.value.spot
    preemptible  = each.value.preemptible

    # Use dedicated service account instead of default compute SA
    service_account = google_service_account.node_pool[each.key].email
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform",
    ]

    # Enable Workload Identity on nodes
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    # Shielded VM configuration
    shielded_instance_config {
      enable_secure_boot          = true
      enable_integrity_monitoring = true
    }

    labels = merge(local.common_labels, each.value.node_labels)
    tags   = ["gke-node", "${local.cluster_name}-${each.key}"]

    dynamic "taint" {
      for_each = each.value.node_taints
      content {
        key    = taint.value.key
        value  = taint.value.value
        effect = taint.value.effect
      }
    }

    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  lifecycle {
    ignore_changes = [
      node_config[0].labels,
    ]
  }
}
