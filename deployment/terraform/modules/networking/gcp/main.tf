###############################################################################
# Networking Module - GCP
# Creates VPC, subnets, Cloud NAT, Cloud Router, and firewall rules
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

locals {
  network_name = var.network_name != "" ? var.network_name : "${var.project_name}-${var.environment}-vpc"

  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_name
  })
}

# -----------------------------------------------------------------------------
# VPC Network
# Custom-mode VPC with no auto-created subnets for full control over IP ranges
# -----------------------------------------------------------------------------

resource "google_compute_network" "vpc" {
  project                 = var.project_id
  name                    = local.network_name
  auto_create_subnetworks = false
  routing_mode            = "REGIONAL"
  description             = "VPC network for ${var.project_name} ${var.environment} environment"
}

# -----------------------------------------------------------------------------
# Subnets
# Three subnets: GKE (with secondary ranges for pods/services), database, public
# All subnets have Private Google Access enabled
# -----------------------------------------------------------------------------

resource "google_compute_subnetwork" "gke" {
  project                  = var.project_id
  name                     = "${local.network_name}-gke"
  ip_cidr_range            = var.gke_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "GKE subnet with secondary ranges for pods and services"

  secondary_ip_range {
    range_name    = "${local.network_name}-pods"
    ip_cidr_range = var.pod_cidr
  }

  secondary_ip_range {
    range_name    = "${local.network_name}-services"
    ip_cidr_range = var.service_cidr
  }

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "database" {
  project                  = var.project_id
  name                     = "${local.network_name}-database"
  ip_cidr_range            = var.database_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Subnet for managed database services"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

resource "google_compute_subnetwork" "public" {
  project                  = var.project_id
  name                     = "${local.network_name}-public"
  ip_cidr_range            = var.public_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc.id
  private_ip_google_access = true
  description              = "Public subnet for load balancers and ingress"

  log_config {
    aggregation_interval = "INTERVAL_5_SEC"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# -----------------------------------------------------------------------------
# Cloud Router and Cloud NAT
# Provides outbound internet access for private GKE nodes
# -----------------------------------------------------------------------------

resource "google_compute_router" "router" {
  project = var.project_id
  name    = "${local.network_name}-router"
  region  = var.region
  network = google_compute_network.vpc.id

  bgp {
    asn = 64514
  }
}

resource "google_compute_address" "nat_ip" {
  project      = var.project_id
  name         = "${local.network_name}-nat-ip"
  region       = var.region
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  labels = local.common_labels
}

resource "google_compute_router_nat" "nat" {
  project = var.project_id
  name    = "${local.network_name}-nat"
  router  = google_compute_router.router.name
  region  = var.region

  nat_ip_allocate_option = "MANUAL_ONLY"
  nat_ips                = [google_compute_address.nat_ip.self_link]

  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.gke.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  subnetwork {
    name                    = google_compute_subnetwork.database.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }

  min_ports_per_vm                    = 256
  max_ports_per_vm                    = 4096
  enable_dynamic_port_allocation      = true
  enable_endpoint_independent_mapping = false
}

# -----------------------------------------------------------------------------
# Firewall Rules
# Controls traffic flow between subnets, health checks, and external access
# -----------------------------------------------------------------------------

resource "google_compute_firewall" "allow_internal" {
  project     = var.project_id
  name        = "${local.network_name}-allow-internal"
  network     = google_compute_network.vpc.id
  description = "Allow all internal traffic between subnets"
  priority    = 1000
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
  }

  allow {
    protocol = "udp"
  }

  allow {
    protocol = "icmp"
  }

  source_ranges = [
    var.gke_subnet_cidr,
    var.database_subnet_cidr,
    var.public_subnet_cidr,
    var.pod_cidr,
    var.service_cidr,
  ]
}

resource "google_compute_firewall" "allow_health_checks" {
  project     = var.project_id
  name        = "${local.network_name}-allow-health-checks"
  network     = google_compute_network.vpc.id
  description = "Allow GCP health check probes from known IP ranges"
  priority    = 900
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
  }

  # Google health check source ranges
  source_ranges = [
    "130.211.0.0/22",
    "35.191.0.0/16",
  ]

  target_tags = ["gke-node"]
}

resource "google_compute_firewall" "allow_ingress_http_https" {
  project     = var.project_id
  name        = "${local.network_name}-allow-ingress-http-https"
  network     = google_compute_network.vpc.id
  description = "Allow HTTP and HTTPS traffic from the internet to public subnet"
  priority    = 1000
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["http-server", "https-server"]
}

resource "google_compute_firewall" "database_access" {
  project     = var.project_id
  name        = "${local.network_name}-database-access"
  network     = google_compute_network.vpc.id
  description = "Restrict database access to GKE subnet only (MongoDB, Redis, Kafka)"
  priority    = 1000
  direction   = "INGRESS"

  allow {
    protocol = "tcp"
    ports    = ["27017", "6379", "9092"]
  }

  source_ranges = [
    var.gke_subnet_cidr,
    var.pod_cidr,
  ]

  target_tags = ["database"]
}
