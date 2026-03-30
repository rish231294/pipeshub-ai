###############################################################################
# Secrets Module - GCP
# Creates Google Secret Manager secrets with IAM bindings for Workload
# Identity and deploys External Secrets Operator via Helm
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }
  }
}

locals {
  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_name
  })

  eso_sa_name = "${var.project_name}-${var.environment}-eso"
}

# -----------------------------------------------------------------------------
# Google Secret Manager Secrets
# One secret per entry in the secrets_map variable
# -----------------------------------------------------------------------------

resource "google_secret_manager_secret" "secrets" {
  for_each = var.secrets_map

  project   = var.project_id
  secret_id = "${var.project_name}-${var.environment}-${each.key}"

  labels = local.common_labels

  replication {
    auto {}
  }
}

resource "google_secret_manager_secret_version" "versions" {
  for_each = var.secrets_map

  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = each.value
}

# -----------------------------------------------------------------------------
# IAM Bindings
# Grant the GKE workload service account access to read secrets
# -----------------------------------------------------------------------------

resource "google_secret_manager_secret_iam_member" "gke_access" {
  for_each = var.gke_service_account_email != "" ? var.secrets_map : {}

  project   = var.project_id
  secret_id = google_secret_manager_secret.secrets[each.key].secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${var.gke_service_account_email}"
}

# -----------------------------------------------------------------------------
# External Secrets Operator (ESO)
# Syncs GCP Secret Manager secrets into Kubernetes secrets
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "eso" {
  metadata {
    name = var.namespace
    labels = merge(local.common_labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "secrets"
    })
  }
}

# GCP service account for ESO to access Secret Manager
resource "google_service_account" "eso" {
  project      = var.project_id
  account_id   = local.eso_sa_name
  display_name = "External Secrets Operator service account for ${var.project_name} ${var.environment}"
}

# Grant ESO service account permission to access secrets
resource "google_project_iam_member" "eso_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.eso.email}"
}

# Workload Identity binding: allow the ESO Kubernetes SA to impersonate the GCP SA
resource "google_service_account_iam_member" "eso_workload_identity" {
  count = var.workload_identity_pool != "" ? 1 : 0

  service_account_id = google_service_account.eso.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.workload_identity_pool}[${var.namespace}/external-secrets]"
}

# Install External Secrets Operator via Helm
resource "helm_release" "external_secrets" {
  name       = "external-secrets"
  repository = "https://charts.external-secrets.io"
  chart      = "external-secrets"
  version    = "0.10.7"
  namespace  = var.namespace
  timeout    = 600
  wait       = true
  atomic     = true

  set {
    name  = "installCRDs"
    value = "true"
  }

  # Annotate the ESO Kubernetes SA with the GCP SA email for Workload Identity
  set {
    name  = "serviceAccount.annotations.iam\\.gke\\.io/gcp-service-account"
    value = google_service_account.eso.email
  }

  depends_on = [
    kubernetes_namespace.eso,
    google_service_account_iam_member.eso_workload_identity,
  ]
}
