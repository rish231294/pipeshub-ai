# -----------------------------------------------------------------------------
# PipesHub AI - GCP Production Environment Values
# -----------------------------------------------------------------------------

environment            = "production"
project_name           = "pipeshub-ai"
# project_id           = "your-gcp-project-id"  # Must be set via -var or environment
region                 = "us-central1"
vpc_cidr               = "10.0.0.0/16"
gke_kubernetes_version = "1.30"

node_pools = {
  system = {
    machine_type  = "e2-standard-4"
    min_count     = 3
    max_count     = 5
    initial_count = 3
    disk_size_gb  = 100
    disk_type     = "pd-ssd"
    labels        = { "pipeshub.ai/node-pool" = "system" }
    taints        = []
    preemptible   = false
    spot          = false
  }
  application = {
    machine_type  = "e2-standard-8"
    min_count     = 3
    max_count     = 10
    initial_count = 3
    disk_size_gb  = 200
    disk_type     = "pd-ssd"
    labels        = { "pipeshub.ai/node-pool" = "application" }
    taints        = []
    preemptible   = false
    spot          = false
  }
  data = {
    machine_type  = "e2-highmem-8"
    min_count     = 2
    max_count     = 4
    initial_count = 2
    disk_size_gb  = 500
    disk_type     = "pd-ssd"
    labels        = { "pipeshub.ai/node-pool" = "data" }
    taints        = []
    preemptible   = false
    spot          = false
  }
}

mongodb_instance_tier    = "M30"
mongodb_disk_size_gb     = 100
redis_memory_size_gb     = 10
redis_tier               = "STANDARD_HA"
kafka_broker_count       = 3
kafka_broker_machine_type = "e2-standard-8"
kafka_disk_size_gb       = 500

domain_name       = "pipeshub.example.com"
create_dns_zone   = false
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
  memory_limit   = "8Gi"
  memory_request = "4Gi"
}
