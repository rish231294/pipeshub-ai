# -----------------------------------------------------------------------------
# Global Bootstrap - Azure Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project, used as prefix for all resources"
  type        = string
  default     = "pipeshub-ai"
}

variable "location" {
  description = "Azure region for the bootstrap resources"
  type        = string
  default     = "eastus"
}

variable "tags" {
  description = "Tags to apply to all bootstrap resources"
  type        = map(string)
  default = {
    Project   = "pipeshub-ai"
    ManagedBy = "terraform"
    Purpose   = "bootstrap"
  }
}
