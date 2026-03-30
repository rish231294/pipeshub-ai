###############################################################################
# DocumentDB Module - AWS
# Creates Amazon DocumentDB (MongoDB-compatible) cluster with subnet group,
# parameter group, Secrets Manager integration, and automated backups
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

  cluster_identifier = var.cluster_identifier != "" ? var.cluster_identifier : "${var.project_name}-${var.environment}-docdb"
}

###############################################################################
# Master Password
###############################################################################

resource "random_password" "master" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:,.<>?"
}

resource "aws_secretsmanager_secret" "master_password" {
  name                    = "${var.project_name}/${var.environment}/documentdb/master-password"
  description             = "Master password for DocumentDB cluster ${local.cluster_identifier}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "master_password" {
  secret_id = aws_secretsmanager_secret.master_password.id
  secret_string = jsonencode({
    username = var.master_username
    password = random_password.master.result
    engine   = "docdb"
    host     = aws_docdb_cluster.main.endpoint
    port     = aws_docdb_cluster.main.port
  })
}

###############################################################################
# Subnet Group
###############################################################################

resource "aws_docdb_subnet_group" "main" {
  name       = "${local.cluster_identifier}-subnet-group"
  subnet_ids = var.database_subnet_ids

  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-subnet-group"
  })
}

###############################################################################
# Parameter Group
###############################################################################

resource "aws_docdb_cluster_parameter_group" "main" {
  family      = "docdb5.0"
  name        = "${local.cluster_identifier}-params"
  description = "Parameter group for ${local.cluster_identifier}"

  parameter {
    name  = "tls"
    value = "enabled"
  }

  parameter {
    name  = "audit_logs"
    value = var.environment == "prod" ? "enabled" : "disabled"
  }

  parameter {
    name  = "ttl_monitor"
    value = "enabled"
  }

  tags = local.common_tags
}

###############################################################################
# Security Group
###############################################################################

resource "aws_security_group" "docdb" {
  name_prefix = "${local.cluster_identifier}-"
  description = "Security group for DocumentDB cluster ${local.cluster_identifier}"
  vpc_id      = var.vpc_id

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      description     = "MongoDB protocol from allowed security group"
      from_port       = 27017
      to_port         = 27017
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
    Name = "${local.cluster_identifier}-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# DocumentDB Cluster
###############################################################################

resource "aws_docdb_cluster" "main" {
  cluster_identifier              = local.cluster_identifier
  engine                          = "docdb"
  engine_version                  = var.engine_version
  master_username                 = var.master_username
  master_password                 = random_password.master.result
  db_subnet_group_name            = aws_docdb_subnet_group.main.name
  db_cluster_parameter_group_name = aws_docdb_cluster_parameter_group.main.name
  vpc_security_group_ids          = [aws_security_group.docdb.id]

  backup_retention_period = var.backup_retention_period
  preferred_backup_window = "03:00-05:00"
  skip_final_snapshot     = var.environment != "prod"
  final_snapshot_identifier = var.environment == "prod" ? "${local.cluster_identifier}-final-snapshot" : null

  storage_encrypted = true
  deletion_protection = var.environment == "prod"

  tags = merge(local.common_tags, {
    Name = local.cluster_identifier
  })
}

###############################################################################
# DocumentDB Instances
###############################################################################

resource "aws_docdb_cluster_instance" "main" {
  count = var.instance_count

  identifier         = "${local.cluster_identifier}-${count.index + 1}"
  cluster_identifier = aws_docdb_cluster.main.id
  instance_class     = var.instance_class
  engine             = "docdb"

  auto_minor_version_upgrade = true

  tags = merge(local.common_tags, {
    Name = "${local.cluster_identifier}-${count.index + 1}"
  })
}
