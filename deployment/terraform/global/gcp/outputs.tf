# -----------------------------------------------------------------------------
# Global Bootstrap - GCP Outputs
# -----------------------------------------------------------------------------

output "state_bucket_name" {
  description = "Name of the GCS bucket used for Terraform state"
  value       = google_storage_bucket.terraform_state.name
}

output "artifact_registry_url" {
  description = "URL of the Artifact Registry repository for Docker images"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.pipeshub.repository_id}"
}
