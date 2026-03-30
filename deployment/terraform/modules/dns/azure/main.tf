###############################################################################
# DNS Module - Azure
# Creates DNS zone (or references existing), installs cert-manager with
# Let's Encrypt, NGINX Ingress Controller, and configures DNS records
###############################################################################

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
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
  common_tags = merge(var.tags, {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
    module      = "dns"
  })
}

# -----------------------------------------------------------------------------
# Azure DNS Zone
# -----------------------------------------------------------------------------

resource "azurerm_dns_zone" "this" {
  count = var.create_zone ? 1 : 0

  name                = var.domain_name
  resource_group_name = var.resource_group_name
  tags                = local.common_tags
}

data "azurerm_dns_zone" "existing" {
  count = var.create_zone ? 0 : 1

  name                = var.domain_name
  resource_group_name = var.resource_group_name
}

locals {
  zone_id      = var.create_zone ? azurerm_dns_zone.this[0].id : data.azurerm_dns_zone.existing[0].id
  zone_name    = var.create_zone ? azurerm_dns_zone.this[0].name : data.azurerm_dns_zone.existing[0].name
  name_servers = var.create_zone ? azurerm_dns_zone.this[0].name_servers : data.azurerm_dns_zone.existing[0].name_servers
}

# -----------------------------------------------------------------------------
# cert-manager - Namespace and Helm Release
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "cert_manager" {
  metadata {
    name = var.cert_manager_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "certificate-management"
    }
  }
}

resource "helm_release" "cert_manager" {
  name       = "cert-manager"
  repository = "https://charts.jetstack.io"
  chart      = "cert-manager"
  namespace  = var.cert_manager_namespace
  version    = "v1.14.4"
  wait       = true
  timeout    = 300

  set {
    name  = "crds.enabled"
    value = "true"
  }

  set {
    name  = "global.leaderElection.namespace"
    value = var.cert_manager_namespace
  }

  depends_on = [kubernetes_namespace.cert_manager]
}

# -----------------------------------------------------------------------------
# Let's Encrypt ClusterIssuer
# -----------------------------------------------------------------------------

resource "kubernetes_manifest" "letsencrypt_prod" {
  count = var.cert_manager_email != "" ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-prod"
    }
    spec = {
      acme = {
        email  = var.cert_manager_email
        server = "https://acme-v2.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-prod-account-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

resource "kubernetes_manifest" "letsencrypt_staging" {
  count = var.cert_manager_email != "" ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        email  = var.cert_manager_email
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        privateKeySecretRef = {
          name = "letsencrypt-staging-account-key"
        }
        solvers = [
          {
            http01 = {
              ingress = {
                class = "nginx"
              }
            }
          }
        ]
      }
    }
  }

  depends_on = [helm_release.cert_manager]
}

# -----------------------------------------------------------------------------
# NGINX Ingress Controller - Namespace and Helm Release
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "ingress" {
  metadata {
    name = var.ingress_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/component"  = "ingress"
    }
  }
}

resource "helm_release" "ingress_nginx" {
  name       = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  namespace  = var.ingress_namespace
  version    = "4.10.0"
  wait       = true
  timeout    = 300

  set {
    name  = "controller.replicaCount"
    value = tostring(var.ingress_replica_count)
  }

  set {
    name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/azure-load-balancer-health-probe-request-path"
    value = "/healthz"
  }

  set {
    name  = "controller.service.externalTrafficPolicy"
    value = "Local"
  }

  set {
    name  = "controller.metrics.enabled"
    value = "true"
  }

  set {
    name  = "controller.podAnnotations.prometheus\\.io/scrape"
    value = "true"
  }

  set {
    name  = "controller.podAnnotations.prometheus\\.io/port"
    value = "10254"
  }

  depends_on = [kubernetes_namespace.ingress]
}

# -----------------------------------------------------------------------------
# DNS A Record pointing to Ingress Controller Load Balancer
# The ingress LB IP is retrieved from the ingress-nginx service after deploy
# -----------------------------------------------------------------------------

data "kubernetes_service" "ingress_nginx" {
  metadata {
    name      = "ingress-nginx-controller"
    namespace = var.ingress_namespace
  }

  depends_on = [helm_release.ingress_nginx]
}

resource "azurerm_dns_a_record" "ingress" {
  name                = "@"
  zone_name           = local.zone_name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip]
  tags                = local.common_tags
}

resource "azurerm_dns_a_record" "wildcard" {
  name                = "*"
  zone_name           = local.zone_name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip]
  tags                = local.common_tags
}
