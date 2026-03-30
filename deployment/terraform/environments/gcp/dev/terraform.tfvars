# -----------------------------------------------------------------------------
# PipesHub AI - GCP Dev Environment Values
# -----------------------------------------------------------------------------

environment            = "dev"
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
    disk_type     = "pd-standard"
    labels        = { "pipeshub.ai/node-pool" = "system" }
    taints        = []
    preemptible   = false
    spot          = false
  }
  application = {
    machine_type  = "e2-standard-4"
    min_count     = 1
    max_count     = 2
    initial_count = 1
    disk_size_gb  = 100
    disk_type     = "pd-ssd"
    labels        = { "pipeshub.ai/node-pool" = "application" }
    taints        = []
    preemptible   = false
    spot          = true
  }
  data = {
    machine_type  = "e2-highmem-4"
    min_count     = 1
    max_count     = 2
    initial_count = 1
    disk_size_gb  = 100
    disk_type     = "pd-ssd"
    labels        = { "pipeshub.ai/node-pool" = "data" }
    taints        = []
    preemptible   = false
    spot          = false
  }
}

mongodb_instance_tier = "db-f1-micro"
mongodb_disk_size_gb  = 20
redis_memory_size_gb  = 1
redis_tier            = "BASIC"
kafka_broker_count    = 2
kafka_broker_machine_type = "e2-standard-2"
kafka_disk_size_gb    = 100

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
