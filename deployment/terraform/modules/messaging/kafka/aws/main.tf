###############################################################################
# Kafka (MSK) Module - AWS
# Creates Amazon MSK cluster with SASL/SCRAM authentication,
# TLS encryption, CloudWatch logging, and Secrets Manager integration
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

  cluster_name = var.cluster_name != "" ? var.cluster_name : "${var.project_name}-${var.environment}-msk"
}

###############################################################################
# SASL/SCRAM Credentials
###############################################################################

resource "random_password" "sasl_password" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]{}|:,.<>?"
}

resource "aws_secretsmanager_secret" "sasl_credentials" {
  name       = "AmazonMSK_${local.cluster_name}_credentials"
  kms_key_id = aws_kms_key.msk.key_id

  description             = "SASL/SCRAM credentials for MSK cluster ${local.cluster_name}"
  recovery_window_in_days = var.environment == "prod" ? 30 : 0

  tags = local.common_tags
}

resource "aws_secretsmanager_secret_version" "sasl_credentials" {
  secret_id = aws_secretsmanager_secret.sasl_credentials.id
  secret_string = jsonencode({
    username = "pipeshub-kafka-user"
    password = random_password.sasl_password.result
  })
}

resource "aws_secretsmanager_secret_policy" "sasl_credentials" {
  secret_arn = aws_secretsmanager_secret.sasl_credentials.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AWSKafkaResourcePolicy"
        Effect    = "Allow"
        Principal = { Service = "kafka.amazonaws.com" }
        Action    = "secretsmanager:getSecretValue"
        Resource  = aws_secretsmanager_secret.sasl_credentials.arn
      }
    ]
  })
}

###############################################################################
# KMS Key for MSK encryption
###############################################################################

resource "aws_kms_key" "msk" {
  description             = "KMS key for MSK cluster ${local.cluster_name}"
  deletion_window_in_days = var.environment == "prod" ? 30 : 7
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "msk" {
  name          = "alias/${local.cluster_name}-msk"
  target_key_id = aws_kms_key.msk.key_id
}

###############################################################################
# Security Group
###############################################################################

resource "aws_security_group" "msk" {
  name_prefix = "${local.cluster_name}-"
  description = "Security group for MSK cluster ${local.cluster_name}"
  vpc_id      = var.vpc_id

  # Kafka plaintext
  ingress {
    description = "Kafka inter-broker and client (plaintext)"
    from_port   = 9092
    to_port     = 9092
    protocol    = "tcp"
    self        = true
  }

  # Kafka TLS
  ingress {
    description = "Kafka TLS"
    from_port   = 9094
    to_port     = 9094
    protocol    = "tcp"
    self        = true
  }

  # Kafka SASL/SCRAM
  ingress {
    description = "Kafka SASL/SCRAM"
    from_port   = 9096
    to_port     = 9096
    protocol    = "tcp"
    self        = true
  }

  # ZooKeeper
  ingress {
    description = "ZooKeeper"
    from_port   = 2181
    to_port     = 2181
    protocol    = "tcp"
    self        = true
  }

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      description     = "Kafka access from allowed security group"
      from_port       = 9092
      to_port         = 9098
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.allowed_security_group_ids
    content {
      description     = "ZooKeeper access from allowed security group"
      from_port       = 2181
      to_port         = 2181
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
    Name = "${local.cluster_name}-msk-sg"
  })

  lifecycle {
    create_before_destroy = true
  }
}

###############################################################################
# CloudWatch Log Group
###############################################################################

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/aws/msk/${local.cluster_name}"
  retention_in_days = var.environment == "prod" ? 90 : 30

  tags = local.common_tags
}

###############################################################################
# MSK Configuration
###############################################################################

resource "aws_msk_configuration" "main" {
  name              = "${local.cluster_name}-config"
  kafka_versions    = [var.kafka_version]
  description       = "MSK configuration for ${local.cluster_name}"

  server_properties = <<-PROPERTIES
    auto.create.topics.enable=true
    log.retention.hours=24
    default.replication.factor=${min(var.broker_count, 3)}
    min.insync.replicas=${min(var.broker_count, 2)}
    num.partitions=3
    num.io.threads=8
    num.network.threads=5
    socket.send.buffer.bytes=102400
    socket.receive.buffer.bytes=102400
    socket.request.max.bytes=104857600
    group.initial.rebalance.delay.ms=3000
    log.segment.bytes=1073741824
    log.retention.check.interval.ms=300000
    unclean.leader.election.enable=false
  PROPERTIES
}

###############################################################################
# MSK Cluster
###############################################################################

resource "aws_msk_cluster" "main" {
  cluster_name           = local.cluster_name
  kafka_version          = var.kafka_version
  number_of_broker_nodes = var.broker_count

  configuration_info {
    arn      = aws_msk_configuration.main.arn
    revision = aws_msk_configuration.main.latest_revision
  }

  broker_node_group_info {
    instance_type  = var.broker_instance_type
    client_subnets = var.database_subnet_ids

    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = var.ebs_volume_size
      }
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn

    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  client_authentication {
    sasl {
      scram = true
    }
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = local.cluster_name
  })
}

###############################################################################
# Associate SCRAM Secret with MSK Cluster
###############################################################################

resource "aws_msk_scram_secret_association" "main" {
  cluster_arn     = aws_msk_cluster.main.arn
  secret_arn_list = [aws_secretsmanager_secret.sasl_credentials.arn]

  depends_on = [aws_secretsmanager_secret_version.sasl_credentials]
}
