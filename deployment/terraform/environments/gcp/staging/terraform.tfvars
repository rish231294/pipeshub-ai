# -----------------------------------------------------------------------------
# PipesHub AI - GCP Staging Environment Values
# -----------------------------------------------------------------------------

environment            = "staging"
project_name           = "pipeshub-ai"
# project_id           = "your-gcp-project-id"  # Must be set via -var or environment
region                 = "us-central1"
vpc_cidr               = "10.0.0.0/16"
gke_kubernetes_version = "1.30"

node_pools = {
  system = {
    machine_type  = "e2-standard-2"
    min_count     = 2
    max_count     = 3
    initial_count = 2
    disk_size_gb  = 50
    disk_type     = "pd-ssd"
    labels        = { "pipeshub.ai/node-pool" = "system" }
    taints        = []
    preemptible   = false
    spot          = false
  }
  application = {
    machine_type  = "e2-standard-8"
    min_count     = 1
    max_count     = 3
    initial_count = 2
    disk_size_gb  = 100
    disk_type     = "pd-ssd"
    labels        = { "pipeshub.ai/node-pool" = "application" }
    taints        = []
    preemptible   = false
    spot          = false
  }
  data = {
    machine_type  = "e2-highmem-4"
    min_count     = 1
    max_count     = 2
    initial_count = 1
    disk_size_gb  = 200
    disk_type     = "pd-ssd"
    labels        = { "pipeshub.ai/node-pool" = "data" }
    taints        = []
    preemptible   = false
    spot          = false
  }
}

mongodb_instance_tier    = "M10"
mongodb_disk_size_gb     = 50
redis_memory_size_gb     = 5
redis_tier               = "STANDARD_HA"
kafka_broker_count       = 3
kafka_broker_machine_type = "e2-standard-4"
kafka_disk_size_gb       = 200

domain_name       = "staging.pipeshub.example.com"
create_dns_zone   = true
app_namespace     = "pipeshub"
kv_store_type     = "etcd"
data_store        = "arangodb"
image_tag         = "latest"
image_repository  = "pipeshubai/pipeshub-ai"
app_replica_count = 2
log_level         = "info"

arangodb_storage_size   = "20Gi"
arangodb_cpu_request    = "1000m"
arangodb_cpu_limit      = "2000m"
arangodb_memory_request = "2Gi"
arangodb_memory_limit   = "4Gi"

qdrant_storage_size   = "30Gi"
qdrant_cpu_request    = "1000m"
qdrant_cpu_limit      = "2000m"
qdrant_memory_request = "2Gi"
qdrant_memory_limit   = "4Gi"

etcd_storage_size = "5Gi"

app_resources = {
  cpu_limit      = "8"
  cpu_request    = "4"
  memory_limit   = "8Gi"
  memory_request = "4Gi"
}
