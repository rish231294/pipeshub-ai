# -----------------------------------------------------------------------------
# Terraform Backend Configuration - GCP Dev
# State is stored in GCS (created by global/gcp bootstrap)
# -----------------------------------------------------------------------------

terraform {
  backend "gcs" {
    bucket = "pipeshub-ai-terraform-state-PROJECT_ID"
    prefix = "dev"
  }
}
