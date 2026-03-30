# -----------------------------------------------------------------------------
# Global Bootstrap - GCP
# Creates shared resources needed before any environment can be provisioned.
# Run once manually with local state: terraform init && terraform apply
# -----------------------------------------------------------------------------

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# -----------------------------------------------------------------------------
# GCS Bucket for Terraform State
# -----------------------------------------------------------------------------

resource "google_storage_bucket" "terraform_state" {
  name          = "${var.project_name}-terraform-state-${var.project_id}"
  location      = var.region
  force_destroy = false

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true

  labels = var.labels
}

# -----------------------------------------------------------------------------
# Artifact Registry for Docker Images
# -----------------------------------------------------------------------------

resource "google_artifact_registry_repository" "pipeshub" {
  location      = var.region
  repository_id = var.project_name
  description   = "Docker repository for PipesHub AI images"
  format        = "DOCKER"

  labels = var.labels
}

# -----------------------------------------------------------------------------
# Enable Required APIs
# -----------------------------------------------------------------------------

resource "google_project_service" "apis" {
  for_each = toset([
    "container.googleapis.com",
    "compute.googleapis.com",
    "secretmanager.googleapis.com",
    "dns.googleapis.com",
    "redis.googleapis.com",
  ])

  project = var.project_id
  service = each.value

  disable_on_destroy = false
}
