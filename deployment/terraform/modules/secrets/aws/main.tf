###############################################################################
# Secrets Module - AWS
# Creates KMS key, Secrets Manager entries, IAM policies for secret access,
# and installs External Secrets Operator via Helm with IRSA
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.0"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  })

  kms_key_alias = var.kms_key_alias != "" ? var.kms_key_alias : "${var.project_name}-${var.environment}-secrets"
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

###############################################################################
# KMS Key for Secrets Encryption
###############################################################################

resource "aws_kms_key" "secrets" {
  description             = "KMS key for encrypting ${var.project_name} ${var.environment} secrets"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableRootAccountFullAccess"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "AllowSecretsManagerUse"
        Effect = "Allow"
        Principal = {
          AWS = "*"
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "kms:CallerAccount" = data.aws_caller_identity.current.account_id
            "kms:ViaService"    = "secretsmanager.${data.aws_region.current.name}.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.kms_key_alias}"
  target_key_id = aws_kms_key.secrets.key_id
}

###############################################################################
# Secrets Manager Entries
###############################################################################

resource "aws_secretsmanager_secret" "main" {
  for_each = var.secrets_map

  name                    = "${var.project_name}/${var.environment}/${each.key}"
  description             = "Secret ${each.key} for ${var.project_name} ${var.environment}"
  kms_key_id              = aws_kms_key.secrets.arn
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = merge(local.common_tags, {
    SecretName = each.key
  })
}

resource "aws_secretsmanager_secret_version" "main" {
  for_each = var.secrets_map

  secret_id     = aws_secretsmanager_secret.main[each.key].id
  secret_string = each.value
}

###############################################################################
# IAM Policy for Reading Secrets
###############################################################################

resource "aws_iam_policy" "secrets_reader" {
  name        = "${var.project_name}-${var.environment}-secrets-reader"
  description = "Policy allowing read access to ${var.project_name} ${var.environment} secrets"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowGetSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ]
        Resource = "arn:aws:secretsmanager:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:secret:${var.project_name}/${var.environment}/*"
      },
      {
        Sid    = "AllowListSecrets"
        Effect = "Allow"
        Action = [
          "secretsmanager:ListSecrets"
        ]
        Resource = "*"
      },
      {
        Sid    = "AllowKMSDecrypt"
        Effect = "Allow"
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey"
        ]
        Resource = aws_kms_key.secrets.arn
      }
    ]
  })

  tags = local.common_tags
}

###############################################################################
# IRSA Role for External Secrets Operator
###############################################################################

resource "aws_iam_role" "eso" {
  name = "${var.project_name}-${var.environment}-eso-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${var.oidc_provider_url}:sub" = "system:serviceaccount:${var.eks_namespace}:external-secrets"
            "${var.oidc_provider_url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "eso_secrets_reader" {
  role       = aws_iam_role.eso.name
  policy_arn = aws_iam_policy.secrets_reader.arn
}

###############################################################################
# External Secrets Operator - Helm Release
###############################################################################

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = var.eks_namespace
  create_namespace = true
  version          = "0.9.13"

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.eso.arn
  }

  set {
    name  = "serviceAccount.name"
    value = "external-secrets"
  }

  set {
    name  = "installCRDs"
    value = "true"
  }

  set {
    name  = "webhook.port"
    value = "9443"
  }

  values = [
    yamlencode({
      resources = {
        requests = {
          cpu    = "100m"
          memory = "128Mi"
        }
        limits = {
          cpu    = "200m"
          memory = "256Mi"
        }
      }
    })
  ]
}
