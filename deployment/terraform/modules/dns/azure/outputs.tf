###############################################################################
# DNS Module - Azure Outputs
###############################################################################

output "zone_id" {
  description = "ID of the Azure DNS zone"
  value       = local.zone_id
}

output "name_servers" {
  description = "List of name servers for the DNS zone (delegate these at your registrar)"
  value       = local.name_servers
}

output "domain_name" {
  description = "Domain name of the DNS zone"
  value       = local.zone_name
}

output "ingress_lb_ip" {
  description = "External IP address of the NGINX Ingress Controller load balancer"
  value       = data.kubernetes_service.ingress_nginx.status[0].load_balancer[0].ingress[0].ip
}

output "cert_manager_namespace" {
  description = "Namespace where cert-manager is installed"
  value       = var.cert_manager_namespace
}

output "ingress_namespace" {
  description = "Namespace where the NGINX Ingress Controller is installed"
  value       = var.ingress_namespace
}
