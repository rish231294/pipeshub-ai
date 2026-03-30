# -----------------------------------------------------------------------------
# Global Bootstrap - GCP Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project, used as prefix for all resources"
  type        = string
  default     = "pipeshub-ai"
}

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for the bootstrap resources"
  type        = string
  default     = "us-central1"
}

variable "labels" {
  description = "Labels to apply to all bootstrap resources"
  type        = map(string)
  default = {
    project    = "pipeshub-ai"
    managed-by = "terraform"
    purpose    = "bootstrap"
  }
}
