# -----------------------------------------------------------------------------
# PipesHub AI - AWS Staging Environment Values
# -----------------------------------------------------------------------------

environment         = "staging"
project_name        = "pipeshub-ai"
region              = "us-east-1"
vpc_cidr            = "10.1.0.0/16"
availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
eks_cluster_version = "1.30"

node_groups = {
  system = {
    instance_types = ["t3.large"]
    min_size       = 2
    max_size       = 4
    desired_size   = 2
    capacity_type  = "ON_DEMAND"
    disk_size      = 50
    labels         = { "pipeshub.ai/node-group" = "system" }
    taints         = []
  }
  application = {
    instance_types = ["m5.xlarge"]
    min_size       = 2
    max_size       = 4
    desired_size   = 2
    capacity_type  = "ON_DEMAND"
    disk_size      = 100
    labels         = { "pipeshub.ai/node-group" = "application" }
    taints         = []
  }
  data = {
    instance_types = ["r5.xlarge"]
    min_size       = 1
    max_size       = 3
    desired_size   = 2
    capacity_type  = "ON_DEMAND"
    disk_size      = 200
    labels         = { "pipeshub.ai/node-group" = "data" }
    taints         = []
  }
}

mongodb_instance_class     = "db.r5.large"
mongodb_instance_count     = 2
redis_node_type            = "cache.r6g.large"
redis_num_cache_clusters   = 2
kafka_broker_instance_type = "kafka.m5.large"
kafka_broker_count         = 3

domain_name       = "staging.pipeshub.example.com"
create_dns_zone   = true
app_namespace     = "pipeshub"
kv_store_type     = "etcd"
data_store        = "arangodb"
image_tag         = "latest"
image_repository  = "pipeshubai/pipeshub-ai"
app_replica_count = 2
log_level         = "info"

arangodb_storage_size   = "50Gi"
arangodb_cpu_request    = "1000m"
arangodb_cpu_limit      = "2000m"
arangodb_memory_request = "1Gi"
arangodb_memory_limit   = "2Gi"

qdrant_storage_size   = "50Gi"
qdrant_cpu_request    = "1000m"
qdrant_cpu_limit      = "2000m"
qdrant_memory_request = "2Gi"
qdrant_memory_limit   = "4Gi"

etcd_storage_size = "5Gi"

app_resources = {
  cpu_limit      = "4"
  cpu_request    = "2"
  memory_limit   = "8Gi"
  memory_request = "4Gi"
}
