###############################################################################
# Storage Module - GCP Outputs
# Exposes bucket name, URL, and self-link for downstream modules
###############################################################################

output "bucket_name" {
  description = "The name of the GCS bucket"
  value       = google_storage_bucket.main.name
}

output "bucket_url" {
  description = "The gsutil URI of the GCS bucket (gs://bucket-name)"
  value       = google_storage_bucket.main.url
}

output "bucket_self_link" {
  description = "The self-link URI of the GCS bucket"
  value       = google_storage_bucket.main.self_link
}
