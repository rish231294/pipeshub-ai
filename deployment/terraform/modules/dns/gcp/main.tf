###############################################################################
# DNS Module - GCP
# Creates Cloud DNS zone, Google-managed SSL certificate, NGINX Ingress
# Controller, and DNS A record pointing to the ingress IP
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.12.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.25.0"
    }
  }
}

locals {
  # Extract the DNS zone from the domain (e.g., "app.example.com" -> "example.com.")
  dns_zone = join(".", slice(split(".", var.domain_name), length(split(".", var.domain_name)) - 2, length(split(".", var.domain_name))))

  managed_zone_name = var.managed_zone_name != "" ? var.managed_zone_name : "${var.project_name}-${var.environment}-zone"

  common_labels = merge(var.labels, {
    environment = var.environment
    project     = var.project_name
  })
}

# -----------------------------------------------------------------------------
# Cloud DNS Managed Zone
# Create a new zone or reference an existing one
# -----------------------------------------------------------------------------

resource "google_dns_managed_zone" "zone" {
  count = var.create_zone ? 1 : 0

  project     = var.project_id
  name        = local.managed_zone_name
  dns_name    = "${local.dns_zone}."
  description = "DNS zone for ${var.project_name} ${var.environment}"
  visibility  = "public"

  labels = local.common_labels

  dnssec_config {
    state = "on"
  }
}

data "google_dns_managed_zone" "existing" {
  count = var.create_zone ? 0 : 1

  project = var.project_id
  name    = local.managed_zone_name
}

locals {
  zone_name     = var.create_zone ? google_dns_managed_zone.zone[0].name : data.google_dns_managed_zone.existing[0].name
  zone_dns_name = var.create_zone ? google_dns_managed_zone.zone[0].dns_name : data.google_dns_managed_zone.existing[0].dns_name
}

# -----------------------------------------------------------------------------
# Google-Managed SSL Certificate
# Automatically provisions and renews a TLS certificate for the domain
# -----------------------------------------------------------------------------

resource "google_compute_managed_ssl_certificate" "main" {
  project = var.project_id
  name    = "${var.project_name}-${var.environment}-cert"

  managed {
    domains = [var.domain_name]
  }
}

# -----------------------------------------------------------------------------
# NGINX Ingress Controller
# Deployed via Helm for flexible routing and TLS termination
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "ingress" {
  metadata {
    name = "ingress-nginx"
    labels = merge(local.common_labels, {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "ingress"
    })
  }
}

resource "helm_release" "nginx_ingress" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.11.3"
  namespace  = kubernetes_namespace.ingress.metadata[0].name
  timeout    = 600
  wait       = true
  atomic     = true

  set {
    name  = "controller.service.type"
    value = "LoadBalancer"
  }

  set {
    name  = "controller.service.loadBalancerIP"
    value = google_compute_address.ingress_ip.address
  }

  set {
    name  = "controller.config.use-forwarded-headers"
    value = "true"
  }

  set {
    name  = "controller.config.compute-full-forwarded-for"
    value = "true"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  depends_on = [kubernetes_namespace.ingress]
}

# -----------------------------------------------------------------------------
# Static External IP for Ingress
# Reserved IP that is referenced by the DNS A record and NGINX LoadBalancer
# -----------------------------------------------------------------------------

resource "google_compute_address" "ingress_ip" {
  project      = var.project_id
  name         = "${var.project_name}-${var.environment}-ingress-ip"
  region       = "us-central1"
  address_type = "EXTERNAL"
  network_tier = "PREMIUM"

  labels = local.common_labels
}

# -----------------------------------------------------------------------------
# DNS A Record
# Points the domain name to the ingress load balancer IP
# -----------------------------------------------------------------------------

resource "google_dns_record_set" "a_record" {
  project      = var.project_id
  name         = "${var.domain_name}."
  type         = "A"
  ttl          = 300
  managed_zone = local.zone_name
  rrdatas      = [google_compute_address.ingress_ip.address]
}
