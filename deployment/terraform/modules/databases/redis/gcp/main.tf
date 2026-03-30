###############################################################################
# Redis Module - GCP
# Creates a Cloud Memorystore for Redis instance with AUTH and encryption
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
  instance_name = var.instance_name != "" ? var.instance_name : "${var.project_name}-${var.environment}-redis"

  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_name
  })
}

# -----------------------------------------------------------------------------
# Cloud Memorystore for Redis
# Managed Redis instance with optional HA, AUTH, and transit encryption
# -----------------------------------------------------------------------------

resource "google_redis_instance" "main" {
  project        = var.project_id
  name           = local.instance_name
  display_name   = "${var.project_name} ${var.environment} Redis"
  region         = var.region
  tier           = var.tier
  memory_size_gb = var.memory_size_gb
  redis_version  = var.redis_version

  # Network configuration - place in the authorized VPC
  authorized_network = var.network_id

  # Authentication
  auth_enabled = var.auth_enabled

  # Transit encryption (TLS)
  transit_encryption_mode = var.transit_encryption_mode

  # Redis configuration parameters
  redis_configs = {
    maxmemory-policy  = "allkeys-lru"
    notify-keyspace-events = ""
    activedefrag      = "yes"
  }

  # Maintenance window: Sunday 2 AM
  maintenance_policy {
    weekly_maintenance_window {
      day = "SUNDAY"
      start_time {
        hours   = 2
        minutes = 0
        seconds = 0
        nanos   = 0
      }
    }
  }

  labels = local.common_labels

  lifecycle {
    prevent_destroy = false
  }
}
