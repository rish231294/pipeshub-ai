###############################################################################
# Redis (ElastiCache) Module - AWS
# Creates ElastiCache Redis replication group with encryption,
# subnet group, parameter group, and auth token in Secrets Manager
###############################################################################

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

locals {
  common_tags = merge(var.tags, {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  })

  replication_group_id = var.replication_group_id != "" ? var.replication_group_id : "${var.project_name}-${var.environment}-redis"
}

###############################################################################
# Auth Token
###############################################################################

resource "random_password" "auth_token" {
  length           = 64
  special          = true
  override_special = "!&#$^<>-"
}

resource "aws_secretsmanager_secret" "auth_token" {
  name                    = "${var.project_name}/${var.environment}/redis/auth-token"
  description             = "Auth token for ElastiCache Redis ${local.replication_group_id}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "auth_token" {
  secret_id = aws_secretsmanager_secret.auth_token.id
  secret_string = jsonencode({
    auth_token = random_password.auth_token.result
    host       = aws_elasticache_replication_group.main.primary_endpoint_address
    port       = 6379
  })
}

###############################################################################
# Subnet Group
###############################################################################

resource "aws_elasticache_subnet_group" "main" {
  name       = "${local.replication_group_id}-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.replication_group_id}-subnet-group"
  })
}

###############################################################################
# Parameter Group
###############################################################################

resource "aws_elasticache_parameter_group" "main" {
  name   = "${local.replication_group_id}-params"
  family = "redis7"

  description = "Parameter group for ${local.replication_group_id}"

  parameter {
    name  = "maxmemory-policy"
    value = "volatile-lru"
  }

  parameter {
    name  = "notify-keyspace-events"
    value = "Ex"
  }

  tags = local.common_tags
}

###############################################################################
# Security Group
###############################################################################

resource "aws_security_group" "redis" {
  name_prefix = "${local.replication_group_id}-"
  description = "Security group for ElastiCache Redis ${local.replication_group_id}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      description     = "Redis from allowed security group"
      from_port       = 6379
      to_port         = 6379
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(local.common_tags, {
    Name = "${local.replication_group_id}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# ElastiCache Redis Replication Group
###############################################################################

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = local.replication_group_id
  description          = "Redis replication group for ${var.project_name} ${var.environment}"

  engine               = "redis"
  engine_version       = var.engine_version
  node_type            = var.node_type
  num_cache_clusters   = var.num_cache_clusters
  port                 = 6379
  parameter_group_name = aws_elasticache_parameter_group.main.name
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]

  at_rest_encryption_enabled = var.at_rest_encryption
  transit_encryption_enabled = var.transit_encryption
  auth_token                 = var.transit_encryption ? random_password.auth_token.result : null

  automatic_failover_enabled = var.num_cache_clusters > 1
  multi_az_enabled           = var.num_cache_clusters > 1

  snapshot_retention_limit = var.environment == "prod" ? 7 : 1
  snapshot_window          = "03:00-05:00"
  maintenance_window       = "sun:05:00-sun:07:00"

  auto_minor_version_upgrade = true
  apply_immediately          = var.environment != "prod"

  tags = merge(local.common_tags, {
    Name = local.replication_group_id
  })
}
