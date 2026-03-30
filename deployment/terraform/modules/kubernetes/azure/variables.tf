###############################################################################
# Kubernetes Module - Azure Variables
# Defines all input variables for AKS cluster and node pools
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

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.project_name))
    error_message = "Project name must be 3-30 characters, lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "cluster_name" {
  description = "Name of the AKS cluster. If not provided, one will be generated from project_name and environment"
  type        = string
  default     = ""
}

variable "kubernetes_version" {
  description = "Kubernetes version for the AKS cluster. Use 'latest' for the latest stable version or specify a version like '1.29'"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "Name of the resource group where the AKS cluster will be created"
  type        = string
}

variable "location" {
  description = "Azure region for resource deployment"
  type        = string
  default     = "eastus"
}

variable "vnet_subnet_id" {
  description = "ID of the subnet where the AKS nodes will be deployed"
  type        = string
}

variable "dns_prefix" {
  description = "DNS prefix for the AKS cluster. If not provided, one will be generated"
  type        = string
  default     = ""
}

variable "node_pools" {
  description = "Map of additional node pool configurations beyond the system pool"
  type = map(object({
    vm_size         = string
    min_count       = number
    max_count       = number
    node_count      = number
    os_disk_size_gb = optional(number, 128)
    max_pods        = optional(number, 110)
    node_labels     = optional(map(string), {})
    node_taints     = optional(list(string), [])
    priority        = optional(string, "Regular")
    spot_max_price  = optional(number, -1)
    zones           = optional(list(string), [])
  }))
  default = {}
}

variable "system_node_pool_vm_size" {
  description = "VM size for the system node pool"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "system_node_pool_min_count" {
  description = "Minimum number of nodes in the system node pool"
  type        = number
  default     = 2
}

variable "system_node_pool_max_count" {
  description = "Maximum number of nodes in the system node pool"
  type        = number
  default     = 3
}

variable "azure_ad_admin_group_object_ids" {
  description = "List of Azure AD group object IDs that will have admin access to the cluster"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}
