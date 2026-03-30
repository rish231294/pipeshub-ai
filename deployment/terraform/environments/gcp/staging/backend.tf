# -----------------------------------------------------------------------------
# Terraform Backend Configuration - GCP Staging
# State is stored in GCS (created by global/gcp bootstrap)
# -----------------------------------------------------------------------------

terraform {
  backend "gcs" {
    bucket = "pipeshub-ai-terraform-state-PROJECT_ID"
    prefix = "staging"
  }
}
