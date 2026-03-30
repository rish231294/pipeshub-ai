###############################################################################
# DNS Module - AWS Outputs
###############################################################################

output "zone_id" {
  description = "Route53 hosted zone ID"
  value       = local.zone_id
}

output "certificate_arn" {
  description = "ARN of the validated ACM certificate"
  value       = aws_acm_certificate.main.arn
}

output "domain_name" {
  description = "Domain name associated with the hosted zone and certificate"
  value       = var.domain_name
}

output "name_servers" {
  description = "Name servers for the Route53 hosted zone (only populated if zone was created)"
  value       = local.create_zone ? aws_route53_zone.main[0].name_servers : []
}

output "lb_controller_role_arn" {
  description = "ARN of the IAM role for the AWS Load Balancer Controller"
  value       = aws_iam_role.lb_controller.arn
}

output "certificate_status" {
  description = "Status of the ACM certificate"
  value       = aws_acm_certificate.main.status
}
