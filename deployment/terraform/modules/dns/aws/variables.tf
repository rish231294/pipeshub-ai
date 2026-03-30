###############################################################################
# DNS Module - AWS Variables
# Defines all input variables for Route53, ACM, and AWS Load Balancer Controller
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

variable "domain_name" {
  description = "Domain name for the hosted zone and ACM certificate (e.g., pipeshub.example.com)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]+[a-z0-9]$", var.domain_name))
    error_message = "Domain name must be a valid DNS name."
  }
}

variable "zone_id" {
  description = "Existing Route53 hosted zone ID. If provided, skips zone creation"
  type        = string
  default     = ""
}

variable "create_zone" {
  description = "Whether to create a new Route53 hosted zone. Ignored if zone_id is provided"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for AWS Load Balancer Controller)"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC (used for AWS Load Balancer Controller)"
  type        = string
}

variable "region" {
  description = "AWS region for resource deployment"
  type        = string
  default     = "us-east-1"
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
