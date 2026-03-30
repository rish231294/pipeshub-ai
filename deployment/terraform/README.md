# PipesHub AI - Terraform Infrastructure

Infrastructure as Code for deploying PipesHub AI across AWS, Azure, and GCP. Provisions Kubernetes clusters, managed databases, networking, messaging, and the PipesHub application via Helm.

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Terraform | >= 1.5.0 | Infrastructure provisioning |
| aws-cli | >= 2.x | AWS authentication (if using AWS) |
| az-cli | >= 2.x | Azure authentication (if using Azure) |
| gcloud | >= 400.x | GCP authentication (if using GCP) |
| kubectl | >= 1.28 | Kubernetes cluster access |
| helm | >= 3.12 | Application deployment |
| tflint | latest | Terraform linting (optional) |
| tfsec | latest | Security scanning (optional) |
| infracost | latest | Cost estimation (optional) |

## Directory Structure

```
deployment/terraform/
├── Makefile                    # Convenience targets for common operations
├── README.md
├── modules/                   # Reusable Terraform modules
│   ├── application/           # PipesHub Helm chart deployment
│   ├── kubernetes/            # Kubernetes clusters (EKS / AKS / GKE)
│   │   ├── aws/
│   │   ├── azure/
│   │   └── gcp/
│   ├── networking/            # VPC / VNet / VPC networking
│   │   ├── aws/
│   │   ├── azure/
│   │   └── gcp/
│   ├── databases/             # Database modules
│   │   ├── mongodb/           # DocumentDB / CosmosDB / Atlas (per cloud)
│   │   ├── redis/             # ElastiCache / Azure Cache / Memorystore
│   │   ├── arangodb/          # Self-hosted via Helm chart
│   │   ├── qdrant/            # Self-hosted via Helm chart
│   │   └── neo4j/             # Self-hosted via Helm chart
│   ├── messaging/
│   │   └── kafka/             # MSK / Event Hubs / self-hosted
│   ├── kv-store/
│   │   └── etcd/              # Self-hosted via Helm chart
│   └── observability/         # Prometheus, Grafana, logging
├── environments/              # Per-cloud, per-environment configurations
│   ├── aws/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── production/
│   ├── azure/
│   │   ├── dev/
│   │   ├── staging/
│   │   └── production/
│   └── gcp/
│       ├── dev/
│       ├── staging/
│       └── production/
└── global/                    # One-time bootstrap resources per cloud
    ├── aws/                   # S3 state bucket, DynamoDB lock table, ECR
    ├── azure/                 # Storage account for state, ACR
    └── gcp/                   # GCS state bucket, Artifact Registry
```

## Quick Start

### 1. Bootstrap Global Resources

Global resources (state backend, container registry) are created once per cloud account. Run this manually with local state.

```bash
# AWS example
cd deployment/terraform
make init-global CLOUD=aws
make apply-global CLOUD=aws
```

This creates:
- S3 bucket for Terraform state (versioned, encrypted)
- DynamoDB table for state locking
- ECR repository for Docker images

### 2. Configure Your Environment

Create a `terraform.tfvars` file in the target environment directory:

```bash
cd environments/aws/dev
```

```hcl
# terraform.tfvars
project_name = "pipeshub"
environment  = "dev"
region       = "us-east-1"

# Kubernetes
cluster_version = "1.30"
node_groups = {
  general = {
    instance_types = ["t3.large"]
    min_size       = 2
    max_size       = 4
    desired_size   = 2
    capacity_type  = "ON_DEMAND"
    disk_size      = 50
    labels         = {}
    taints         = []
  }
}

# Set to true to use cloud-managed services instead of in-cluster
use_managed_mongo = false
use_managed_redis = false
use_managed_kafka = false
```

### 3. Init, Plan, Apply

```bash
# From deployment/terraform/
make init CLOUD=aws ENV=dev
make plan CLOUD=aws ENV=dev
make apply CLOUD=aws ENV=dev
```

Or use the shortcuts:

```bash
make aws-dev        # Plan AWS dev
make aws-staging    # Plan AWS staging
make azure-dev      # Plan Azure dev
```

### 4. Access Your Cluster

```bash
# AWS
aws eks update-kubeconfig --name pipeshub-dev --region us-east-1

# Azure
az aks get-credentials --resource-group pipeshub-dev-rg --name pipeshub-dev

# GCP
gcloud container clusters get-credentials pipeshub-dev --region us-central1
```

## Multi-Cloud Support

Each cloud provider uses its managed equivalents where available. The application module abstracts this: when a managed endpoint is provided, the corresponding in-cluster component is automatically disabled.

| Component | AWS | Azure | GCP | Self-Hosted |
|-----------|-----|-------|-----|-------------|
| Kubernetes | EKS | AKS | GKE | - |
| MongoDB | DocumentDB | CosmosDB (Mongo API) | MongoDB Atlas | In-cluster |
| Redis | ElastiCache | Azure Cache for Redis | Memorystore | In-cluster |
| Kafka | MSK | Event Hubs (Kafka API) | Confluent on GCP | In-cluster |
| ArangoDB | - | - | - | Helm chart (StatefulSet) |
| Qdrant | - | - | - | Helm chart (StatefulSet) |
| etcd | - | - | - | Helm chart (StatefulSet) |
| Neo4j | - | - | - | Helm chart (optional) |
| Networking | VPC | VNet | VPC | - |
| Container Registry | ECR | ACR | Artifact Registry | - |
| State Backend | S3 + DynamoDB | Azure Storage | GCS | - |

## Environment Configuration

### Dev
- Smaller instance types (e.g., `t3.large`)
- 2-node cluster, autoscaling up to 4
- All databases self-hosted in-cluster (lower cost)
- Public API endpoint enabled
- Relaxed resource limits

### Staging
- Production-like instance types (e.g., `t3.xlarge`)
- 3-node cluster, autoscaling up to 6
- Mix of managed and self-hosted services
- Used for integration testing and pre-release validation
- Requires manual approval for CI/CD apply

### Production
- Production instance types (e.g., `m5.xlarge`)
- 3-node minimum, autoscaling up to 10
- Managed services for MongoDB, Redis, and Kafka
- Private API endpoint, network policies enforced
- Multi-AZ / multi-zone deployment
- Requires manual approval for CI/CD apply
- `prevent_destroy` lifecycle rules on stateful resources

## Managed Services

Toggle between managed cloud services and self-hosted in-cluster deployments using the `managed_service_endpoints` variable. When an endpoint is provided, the in-cluster deployment is disabled and the managed endpoint is injected into the application.

```hcl
# Use managed MongoDB (AWS DocumentDB)
managed_service_endpoints = {
  mongo_uri      = "mongodb://docdb-cluster.cluster-xxxx.us-east-1.docdb.amazonaws.com:27017"
  redis_host     = ""   # Empty = use in-cluster Redis
  kafka_brokers  = ""
  arango_url     = ""
  qdrant_host    = ""
  etcd_url       = ""
  neo4j_uri      = ""
  # ... additional fields
}
```

To use all self-hosted (default for dev):

```hcl
managed_service_endpoints = {
  mongo_uri  = ""
  redis_host = ""
  # ... all empty
}
```

## Security

### OIDC Authentication (CI/CD)

GitHub Actions authenticate to cloud providers using OIDC (OpenID Connect) -- no long-lived credentials are stored. Configure these secrets in your GitHub repository:

| Secret | Provider | Description |
|--------|----------|-------------|
| `AWS_TERRAFORM_ROLE_ARN` | AWS | IAM role ARN for Terraform |
| `AZURE_CLIENT_ID` | Azure | App registration client ID |
| `AZURE_TENANT_ID` | Azure | Azure AD tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Azure | Target subscription |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | GCP | Workload identity provider |
| `GCP_SERVICE_ACCOUNT` | GCP | Service account email |

### Network Isolation

- Kubernetes clusters are deployed in private subnets
- Database security groups restrict access to the cluster VPC CIDR only
- Public endpoint access can be controlled per environment
- Ingress is managed via cloud load balancers with TLS termination

### Secrets Management

- Sensitive values (database passwords, API keys) are passed via `set_sensitive` in Helm
- Use cloud-native secret stores (AWS Secrets Manager, Azure Key Vault, GCP Secret Manager) for production
- Never commit `terraform.tfvars` files containing secrets -- use environment variables or CI/CD secrets

## CI/CD

Three GitHub Actions workflows automate the Terraform lifecycle:

### terraform-plan.yml (Pull Requests)

Triggers on PRs that modify `deployment/terraform/**`. For each affected environment:

1. Detects which `cloud/env` combinations changed (module changes trigger all environments)
2. Runs `terraform fmt -check` for formatting validation
3. Runs `terraform init`, `validate`, and `plan`
4. Posts the plan output as a PR comment
5. Runs tfsec security scan (soft fail)

### terraform-apply.yml (Push to main)

Triggers on merges to `main` that modify `deployment/terraform/**`:

1. Detects changed environments
2. Applies **dev** environments automatically
3. Applies **staging** after dev succeeds (requires manual approval via GitHub environment protection)
4. Applies **production** after staging succeeds (requires manual approval)

### terraform-destroy.yml (Manual)

Manual workflow dispatch only. Requires typing `DESTROY` as confirmation. Production is excluded from the environment options as a safety measure.

## Makefile Usage

All Makefile targets accept `CLOUD` and `ENV` variables (defaults: `aws` and `dev`).

```bash
# Show all available targets
make help

# Lifecycle
make init CLOUD=aws ENV=dev
make plan CLOUD=aws ENV=dev
make apply CLOUD=aws ENV=dev
make destroy CLOUD=aws ENV=staging

# Auto-approve (skip confirmation prompt)
make apply-auto CLOUD=azure ENV=dev

# Formatting and validation
make fmt                           # Format all .tf files recursively
make validate CLOUD=aws ENV=dev    # Validate configuration
make lint CLOUD=aws ENV=dev        # Run tflint

# Security and cost
make security                      # Run tfsec across all modules
make cost CLOUD=aws ENV=dev        # Infracost breakdown

# Plan all environments for one cloud
make plan-all CLOUD=aws

# Global bootstrap
make init-global CLOUD=aws
make apply-global CLOUD=aws
```

## Common Operations

### Adding a New Environment

1. Create the directory:
   ```bash
   mkdir -p environments/aws/qa
   ```

2. Copy from an existing environment and adjust:
   ```bash
   cp environments/aws/dev/*.tf environments/aws/qa/
   ```

3. Update `terraform.tfvars` with environment-specific values.

4. Update CI/CD workflows if automatic plan/apply is needed.

### Scaling Node Groups

Edit `terraform.tfvars` for the target environment:

```hcl
node_groups = {
  general = {
    min_size     = 3
    max_size     = 10
    desired_size = 5
    # ...
  }
}
```

Then run:

```bash
make plan CLOUD=aws ENV=production
make apply CLOUD=aws ENV=production
```

### Upgrading Kubernetes Version

1. Check the provider's supported versions.
2. Update `cluster_version` in `terraform.tfvars`:
   ```hcl
   cluster_version = "1.31"
   ```
3. Plan and review the changes carefully -- cluster upgrades are in-place but may cause brief API unavailability.
4. Apply the change. Node groups will be updated on the next rolling update.

### Switching a Service to Managed

To move from self-hosted Redis to AWS ElastiCache:

1. Provision the managed service by setting `use_managed_redis = true` in your environment config.
2. Migrate data from the in-cluster Redis to ElastiCache.
3. Update `managed_service_endpoints.redis_host` with the ElastiCache endpoint.
4. Apply -- the in-cluster Redis pod will be removed and the app will connect to ElastiCache.

## Troubleshooting

### State Lock Errors

```
Error: Error acquiring the state lock
```

If a previous apply was interrupted, the lock may be stuck. Release it:

```bash
cd environments/aws/dev
terraform force-unlock <LOCK_ID>
```

### Provider Authentication Failures

Ensure your cloud CLI is authenticated:

```bash
# AWS
aws sts get-caller-identity

# Azure
az account show

# GCP
gcloud auth application-default print-access-token
```

### Plan Shows Unexpected Changes

If `terraform plan` shows changes you did not make, it may be due to:

- Another team member applied changes outside of Terraform
- Provider defaults changed between versions
- State drift from manual changes in the cloud console

Run `terraform refresh` to sync state, then review the plan again.

### Helm Release Stuck

If the Helm release is stuck in a pending or failed state:

```bash
helm list -n pipeshub --all
helm rollback pipeshub-ai <REVISION> -n pipeshub
```

### Module Version Conflicts

When upgrading modules, ensure all environments are planned and applied in order (dev, staging, production) to catch breaking changes early.

## Cost Estimation

Approximate monthly costs per environment (varies by region and usage):

| Component | Dev | Staging | Production |
|-----------|-----|---------|------------|
| Kubernetes cluster | $75 (EKS) | $75 | $75 |
| Worker nodes (2-3x) | $120-180 | $250-400 | $500-1500 |
| Managed MongoDB | - (self-hosted) | $200 | $400+ |
| Managed Redis | - (self-hosted) | $50 | $150+ |
| Managed Kafka | - (self-hosted) | $200 | $500+ |
| Networking / LB | $20-40 | $30-50 | $50-100 |
| Storage (EBS/PV) | $20-40 | $50-80 | $100-200 |
| **Estimated Total** | **$235-335** | **$855-1055** | **$1775-2525** |

Use `make cost` for detailed estimates based on your actual configuration:

```bash
make cost CLOUD=aws ENV=production
```

All costs are estimates. Actual costs depend on region, data transfer, and usage patterns. Self-hosted components in dev reduce costs significantly by running databases as pods inside the Kubernetes cluster.
