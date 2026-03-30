###############################################################################
# Storage (S3) Module - AWS Variables
# Defines all input variables for S3 bucket with encryption, lifecycle,
# CORS, and IRSA for pod-level access
###############################################################################

variable "environment" {
  description = "Deployment environment (e.g., dev, staging, prod)"
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be one of: dev, staging, prod."
  }
}

variable "project_name" {
  description = "Name of the project, used for resource naming and tagging"
  type        = string
  default     = "pipeshub"
}

variable "bucket_name" {
  description = "Name for the S3 bucket. Must be globally unique"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "Bucket name must be 3-63 characters, lowercase alphanumeric with dots and hyphens."
  }
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS (e.g., frontend URLs)"
  type        = list(string)
  default     = ["*"]
}

variable "lifecycle_rules_enabled" {
  description = "Enable lifecycle rules for transitioning objects to IA and Glacier"
  type        = bool
  default     = true
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider (without https:// prefix)"
  type        = string
}

variable "eks_namespace" {
  description = "Kubernetes namespace for the service account that will access S3"
  type        = string
  default     = "default"
}

variable "service_account_name" {
  description = "Name of the Kubernetes service account for S3 access"
  type        = string
  default     = "pipeshub-s3-access"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
