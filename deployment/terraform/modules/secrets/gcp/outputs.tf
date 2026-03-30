###############################################################################
# Secrets Module - GCP Outputs
# Exposes secret identifiers and ESO service account details
###############################################################################

output "secret_ids" {
  description = "Map of secret names to their Secret Manager secret IDs"
  value = {
    for name, secret in google_secret_manager_secret.secrets : name => secret.secret_id
  }
}

output "secret_versions" {
  description = "Map of secret names to their latest Secret Manager version IDs"
  value = {
    for name, version in google_secret_manager_secret_version.versions : name => version.id
  }
}

output "eso_service_account_email" {
  description = "Email of the GCP service account used by External Secrets Operator"
  value       = google_service_account.eso.email
}
