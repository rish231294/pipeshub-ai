# -----------------------------------------------------------------------------
# Global Bootstrap - AWS Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name of the project, used as prefix for all resources"
  type        = string
  default     = "pipeshub-ai"
}

variable "region" {
  description = "AWS region for the bootstrap resources"
  type        = string
  default     = "us-east-1"
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
