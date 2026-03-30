# -----------------------------------------------------------------------------
# PipesHub AI - Azure Production Environment Values
# -----------------------------------------------------------------------------

environment            = "production"
project_name           = "pipeshub-ai"
location               = "eastus"
vnet_cidr              = "10.2.0.0/16"
aks_kubernetes_version = "1.30"

node_pools = {
  system = {
    vm_size      = "Standard_D4s_v3"
    min_count    = 3
    max_count    = 5
    node_count   = 3
    os_disk_size = 100
    labels       = { "pipeshub.ai/node-pool" = "system" }
    taints       = []
    priority     = "Regular"
  }
  application = {
    vm_size      = "Standard_D8s_v3"
    min_count    = 3
    max_count    = 6
    node_count   = 3
    os_disk_size = 200
    labels       = { "pipeshub.ai/node-pool" = "application" }
    taints       = []
    priority     = "Regular"
  }
  data = {
    vm_size      = "Standard_E8s_v3"
    min_count    = 2
    max_count    = 4
    node_count   = 3
    os_disk_size = 500
    labels       = { "pipeshub.ai/node-pool" = "data" }
    taints       = []
    priority     = "Regular"
  }
}

cosmos_db_offer_type = "Standard"
cosmos_db_throughput  = 4000
redis_sku_name       = "Premium"
redis_family         = "P"
redis_capacity       = 1
eventhub_sku         = "Standard"
eventhub_capacity    = 4

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
