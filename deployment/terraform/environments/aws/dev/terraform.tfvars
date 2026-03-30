# -----------------------------------------------------------------------------
# PipesHub AI - AWS Dev Environment Values
# -----------------------------------------------------------------------------

environment         = "dev"
project_name        = "pipeshub-ai"
region              = "us-east-1"
vpc_cidr            = "10.0.0.0/16"
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
eks_cluster_version = "1.30"

node_groups = {
  system = {
    instance_types = ["t3.medium"]
    min_size       = 2
    max_size       = 3
    desired_size   = 2
    capacity_type  = "ON_DEMAND"
    disk_size      = 50
    labels         = { "pipeshub.ai/node-group" = "system" }
    taints         = []
  }
  application = {
    instance_types = ["m5.xlarge"]
    min_size       = 1
    max_size       = 2
    desired_size   = 1
    capacity_type  = "SPOT"
    disk_size      = 100
    labels         = { "pipeshub.ai/node-group" = "application" }
    taints         = []
  }
  data = {
    instance_types = ["r5.large"]
    min_size       = 1
    max_size       = 2
    desired_size   = 1
    capacity_type  = "ON_DEMAND"
    disk_size      = 100
    labels         = { "pipeshub.ai/node-group" = "data" }
    taints         = []
  }
}

mongodb_instance_class     = "db.t3.medium"
mongodb_instance_count     = 1
redis_node_type            = "cache.t3.micro"
redis_num_cache_clusters   = 1
kafka_broker_instance_type = "kafka.t3.small"
kafka_broker_count         = 2

domain_name       = "dev.pipeshub.example.com"
create_dns_zone   = true
app_namespace     = "pipeshub"
kv_store_type     = "etcd"
data_store        = "arangodb"
image_tag         = "latest"
image_repository  = "pipeshubai/pipeshub-ai"
app_replica_count = 1
log_level         = "debug"

arangodb_storage_size   = "10Gi"
arangodb_cpu_request    = "500m"
arangodb_cpu_limit      = "1000m"
arangodb_memory_request = "512Mi"
arangodb_memory_limit   = "1Gi"

qdrant_storage_size   = "10Gi"
qdrant_cpu_request    = "500m"
qdrant_cpu_limit      = "1000m"
qdrant_memory_request = "1Gi"
qdrant_memory_limit   = "2Gi"

etcd_storage_size = "1Gi"

app_resources = {
  cpu_limit      = "4"
  cpu_request    = "2"
  memory_limit   = "4Gi"
  memory_request = "2Gi"
}
