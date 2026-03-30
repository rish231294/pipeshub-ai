###############################################################################
# Secrets Module - AWS Outputs
###############################################################################

output "kms_key_arn" {
  description = "ARN of the KMS key used for secrets encryption"
  value       = aws_kms_key.secrets.arn
}

output "kms_key_id" {
  description = "ID of the KMS key used for secrets encryption"
  value       = aws_kms_key.secrets.key_id
}

output "secret_arns" {
  description = "Map of secret names to their ARNs in Secrets Manager"
  value = {
    for k, v in aws_secretsmanager_secret.main : k => v.arn
  }
}

output "eso_iam_role_arn" {
  description = "ARN of the IAM role for External Secrets Operator (IRSA)"
  value       = aws_iam_role.eso.arn
}

output "secrets_reader_policy_arn" {
  description = "ARN of the IAM policy for reading secrets"
  value       = aws_iam_policy.secrets_reader.arn
}
