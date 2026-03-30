###############################################################################
# Kubernetes Module - GCP Variables
# Defines all input variables for GKE cluster and node pools
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
  description = "Name of the project, used for resource naming and labeling"
  type        = string
  default     = "pipeshub"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 3-30 characters, lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "project_id" {
  description = "GCP project ID where resources will be created"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 characters, lowercase alphanumeric with hyphens."
  }
}

variable "region" {
  description = "GCP region for GKE cluster deployment"
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "Name of the GKE cluster"
  type        = string
  default     = ""

  validation {
    condition     = var.cluster_name == "" || can(regex("^[a-z][a-z0-9-]{0,38}[a-z0-9]$", var.cluster_name))
    error_message = "Cluster name must be lowercase alphanumeric with hyphens, starting with a letter, max 40 characters."
  }
}

variable "kubernetes_version" {
  description = "Kubernetes version for the GKE cluster (e.g., 1.30). Leave empty for latest in REGULAR channel"
  type        = string
  default     = ""
}

variable "network_id" {
  description = "Self-link or ID of the VPC network for the cluster"
  type        = string
}

variable "subnet_id" {
  description = "Self-link or ID of the subnet for GKE nodes"
  type        = string
}

variable "pod_secondary_range_name" {
  description = "Name of the secondary IP range in the subnet for pods"
  type        = string
}

variable "service_secondary_range_name" {
  description = "Name of the secondary IP range in the subnet for services"
  type        = string
}

variable "node_pools" {
  description = "Map of node pool configurations. Each key is the pool name."
  type = map(object({
    machine_type   = string
    min_count      = number
    max_count      = number
    disk_size_gb   = optional(number, 100)
    disk_type      = optional(string, "pd-standard")
    spot           = optional(bool, false)
    preemptible    = optional(bool, false)
    node_labels    = optional(map(string), {})
    node_taints    = optional(list(object({
      key    = string
      value  = string
      effect = string
    })), [])
  }))
  default = {
    system = {
      machine_type = "e2-standard-2"
      min_count    = 2
      max_count    = 3
      disk_size_gb = 50
      disk_type    = "pd-standard"
      preemptible  = false
      spot         = false
      node_labels  = { "workload-type" = "system" }
      node_taints  = []
    }
    application = {
      machine_type = "e2-standard-8"
      min_count    = 1
      max_count    = 3
      disk_size_gb = 100
      disk_type    = "pd-standard"
      spot         = false
      preemptible  = false
      node_labels  = { "workload-type" = "application" }
      node_taints  = []
    }
    data = {
      machine_type = "e2-highmem-4"
      min_count    = 1
      max_count    = 2
      disk_size_gb = 200
      disk_type    = "pd-ssd"
      spot         = false
      preemptible  = false
      node_labels  = { "workload-type" = "data" }
      node_taints = [{
        key    = "workload-type"
        value  = "data"
        effect = "NO_SCHEDULE"
      }]
    }
  }
}

variable "master_authorized_networks" {
  description = "List of CIDR blocks authorized to access the GKE master endpoint"
  type = list(object({
    cidr_block   = string
    display_name = string
  }))
  default = []
}

variable "labels" {
  description = "Additional labels to apply to all resources"
  type        = map(string)
  default     = {}
}
