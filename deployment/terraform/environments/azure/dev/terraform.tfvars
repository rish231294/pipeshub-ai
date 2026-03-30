# -----------------------------------------------------------------------------
# PipesHub AI - Azure Dev Environment Values
# -----------------------------------------------------------------------------

environment            = "dev"
project_name           = "pipeshub-ai"
location               = "eastus"
vnet_cidr              = "10.0.0.0/16"
aks_kubernetes_version = "1.30"

node_pools = {
  system = {
    vm_size      = "Standard_D2s_v3"
    min_count    = 2
    max_count    = 3
    node_count   = 2
    os_disk_size = 50
    labels       = { "pipeshub.ai/node-pool" = "system" }
    taints       = []
    priority     = "Regular"
  }
  application = {
    vm_size      = "Standard_D4s_v3"
    min_count    = 1
    max_count    = 2
    node_count   = 1
    os_disk_size = 100
    labels       = { "pipeshub.ai/node-pool" = "application" }
    taints       = []
    priority     = "Spot"
  }
  data = {
    vm_size      = "Standard_E4s_v3"
    min_count    = 1
    max_count    = 2
    node_count   = 1
    os_disk_size = 100
    labels       = { "pipeshub.ai/node-pool" = "data" }
    taints       = []
    priority     = "Regular"
  }
}

cosmos_db_offer_type = "Standard"
cosmos_db_throughput  = 400
redis_sku_name       = "Basic"
redis_family         = "C"
redis_capacity       = 0
eventhub_sku         = "Basic"
eventhub_capacity    = 1

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
