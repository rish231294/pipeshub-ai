###############################################################################
# MongoDB Atlas Module - GCP
# Creates a MongoDB Atlas cluster with VPC peering and database user
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    mongodbatlas = {
      source  = "mongodb/mongodbatlas"
      version = "~> 1.21"
    }
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

locals {
  cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}"

  common_labels = {
    environment = var.environment
    project     = var.project_name
  }
}

# -----------------------------------------------------------------------------
# MongoDB Atlas Cluster
# Deployed on GCP with configurable tier, disk, backup, and auto-scaling
# -----------------------------------------------------------------------------

resource "mongodbatlas_cluster" "main" {
  project_id = var.atlas_project_id
  name       = local.cluster_name

  # GCP cloud provider configuration
  provider_name               = "GCP"
  provider_instance_size_name = var.instance_size
  provider_region_name        = var.region

  # Cluster type: replicaset (standard) for single-region
  cluster_type = "REPLICASET"

  # Storage
  disk_size_gb = var.disk_size_gb

  # Backup
  cloud_backup = var.cloud_backup_enabled

  # Auto-scaling (recommended for production)
  auto_scaling_compute_enabled                    = var.auto_scaling_enabled
  auto_scaling_compute_scale_down_enabled         = var.auto_scaling_enabled
  auto_scaling_disk_gb_enabled                    = var.auto_scaling_enabled

  # Replication specs
  replication_specs {
    num_shards = 1

    regions_config {
      region_name     = var.region
      electable_nodes = 3
      priority        = 7
      read_only_nodes = 0
    }
  }

  # Advanced configuration
  advanced_configuration {
    javascript_enabled           = false
    minimum_enabled_tls_protocol = "TLS1_2"
    no_table_scan               = false
  }

  labels {
    key   = "environment"
    value = var.environment
  }

  labels {
    key   = "project"
    value = var.project_name
  }

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# VPC Peering
# Establishes private connectivity between GCP VPC and MongoDB Atlas
# -----------------------------------------------------------------------------

resource "mongodbatlas_network_peering" "gcp" {
  project_id     = var.atlas_project_id
  container_id   = mongodbatlas_cluster.main.container_id
  provider_name  = "GCP"
  gcp_project_id = var.gcp_project_id
  network_name   = var.network_name
}

# Accept the VPC peering connection on the GCP side
data "google_compute_network" "vpc" {
  project = var.gcp_project_id
  name    = var.network_name
}

resource "google_compute_network_peering" "atlas" {
  name         = "atlas-${local.cluster_name}"
  network      = data.google_compute_network.vpc.self_link
  peer_network = "projects/${mongodbatlas_network_peering.gcp.atlas_gcp_project_id}/global/networks/${mongodbatlas_network_peering.gcp.atlas_vpc_name}"
}

# -----------------------------------------------------------------------------
# Database User
# Application-level user with readWriteAnyDatabase role
# -----------------------------------------------------------------------------

resource "mongodbatlas_database_user" "app" {
  project_id         = var.atlas_project_id
  auth_database_name = "admin"
  username           = var.database_user
  password           = var.database_password

  roles {
    role_name     = "readWriteAnyDatabase"
    database_name = "admin"
  }

  scopes {
    name = mongodbatlas_cluster.main.name
    type = "CLUSTER"
  }

  labels {
    key   = "environment"
    value = var.environment
  }
}

# -----------------------------------------------------------------------------
# IP Access List
# Allows connections from the Atlas VPC peering CIDR
# -----------------------------------------------------------------------------

resource "mongodbatlas_project_ip_access_list" "peering" {
  project_id = var.atlas_project_id
  # Allow the entire GCP VPC CIDR via peering
  cidr_block = mongodbatlas_network_peering.gcp.atlas_cidr_block
  comment    = "GCP VPC peering - ${var.environment}"
}
