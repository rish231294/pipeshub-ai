# -----------------------------------------------------------------------------
# PipesHub AI - AWS Production Environment Values
# -----------------------------------------------------------------------------

environment         = "production"
project_name        = "pipeshub-ai"
region              = "us-east-1"
vpc_cidr            = "10.2.0.0/16"
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
eks_cluster_version = "1.30"

node_groups = {
  system = {
    instance_types = ["t3.xlarge"]
    min_size       = 3
    max_size       = 5
    desired_size   = 3
    capacity_type  = "ON_DEMAND"
    disk_size      = 100
    labels         = { "pipeshub.ai/node-group" = "system" }
    taints         = []
  }
  application = {
    instance_types = ["m5.2xlarge"]
    min_size       = 3
    max_size       = 6
    desired_size   = 3
    capacity_type  = "ON_DEMAND"
    disk_size      = 200
    labels         = { "pipeshub.ai/node-group" = "application" }
    taints         = []
  }
  data = {
    instance_types = ["r5.xlarge"]
    min_size       = 2
    max_size       = 4
    desired_size   = 3
    capacity_type  = "ON_DEMAND"
    disk_size      = 500
    labels         = { "pipeshub.ai/node-group" = "data" }
    taints         = []
  }
}

mongodb_instance_class     = "db.r5.xlarge"
mongodb_instance_count     = 3
redis_node_type            = "cache.r6g.xlarge"
redis_num_cache_clusters   = 3
kafka_broker_instance_type = "kafka.m5.large"
kafka_broker_count         = 3

domain_name       = "pipeshub.example.com"
create_dns_zone   = true
app_namespace     = "pipeshub"
kv_store_type     = "etcd"
data_store        = "arangodb"
image_tag         = "latest"
image_repository  = "pipeshubai/pipeshub-ai"
app_replica_count = 3
log_level         = "warn"

arangodb_storage_size   = "100Gi"
arangodb_cpu_request    = "2000m"
arangodb_cpu_limit      = "4000m"
arangodb_memory_request = "4Gi"
arangodb_memory_limit   = "8Gi"

qdrant_storage_size   = "100Gi"
qdrant_cpu_request    = "2000m"
qdrant_cpu_limit      = "4000m"
qdrant_memory_request = "4Gi"
qdrant_memory_limit   = "8Gi"

etcd_storage_size = "10Gi"

app_resources = {
  cpu_limit      = "8"
  cpu_request    = "4"
  memory_limit   = "16Gi"
  memory_request = "8Gi"
}
