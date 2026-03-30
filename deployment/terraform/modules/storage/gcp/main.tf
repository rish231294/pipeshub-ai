###############################################################################
# Storage Module - GCP
# Creates a Google Cloud Storage bucket with versioning, uniform access,
# lifecycle rules, CORS configuration, and IAM bindings
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
  bucket_name = var.bucket_name != "" ? var.bucket_name : "${var.project_id}-${var.project_name}-${var.environment}"

  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_name
  })
}

# -----------------------------------------------------------------------------
# Google Cloud Storage Bucket
# Object storage with versioning, uniform access, and lifecycle management
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "main" {
  project  = var.project_id
  name     = local.bucket_name
  location = var.location

  storage_class               = var.storage_class
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # Enable versioning for data protection
  versioning {
    enabled = true
  }

  # CORS configuration for frontend direct uploads/downloads
  cors {
    origin          = var.cors_origins
    method          = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    response_header = ["Content-Type", "Content-Disposition", "Content-Length"]
    max_age_seconds = 3600
  }

  # Lifecycle rules: transition to cheaper storage tiers over time
  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules_enabled ? [1] : []
    content {
      action {
        type          = "SetStorageClass"
        storage_class = "NEARLINE"
      }
      condition {
        age = 90
      }
    }
  }

  dynamic "lifecycle_rule" {
    for_each = var.lifecycle_rules_enabled ? [1] : []
    content {
      action {
        type          = "SetStorageClass"
        storage_class = "COLDLINE"
      }
      condition {
        age = 365
      }
    }
  }

  # Delete non-current object versions after 30 days to limit storage costs
  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      num_newer_versions = 3
      with_state         = "ARCHIVED"
    }
  }

  # Soft delete policy for recovery (7-day retention)
  soft_delete_policy {
    retention_duration_seconds = 604800
  }

  labels = local.common_labels

  lifecycle {
    prevent_destroy = false
  }
}

# -----------------------------------------------------------------------------
# IAM Binding
# Grant the GKE workload service account read/write access to the bucket
# -----------------------------------------------------------------------------

resource "google_storage_bucket_iam_member" "gke_object_admin" {
  count = var.gke_service_account_email != "" ? 1 : 0

  bucket = google_storage_bucket.main.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.gke_service_account_email}"
}

resource "google_storage_bucket_iam_member" "gke_bucket_reader" {
  count = var.gke_service_account_email != "" ? 1 : 0

  bucket = google_storage_bucket.main.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${var.gke_service_account_email}"
}
