# -----------------------------------------------------------------------------
# PipesHub AI - Azure Staging Environment Values
# -----------------------------------------------------------------------------

environment            = "staging"
project_name           = "pipeshub-ai"
location               = "eastus"
vnet_cidr              = "10.1.0.0/16"
aks_kubernetes_version = "1.30"

node_pools = {
  system = {
    vm_size      = "Standard_D4s_v3"
    min_count    = 2
    max_count    = 4
    node_count   = 2
    os_disk_size = 50
    labels       = { "pipeshub.ai/node-pool" = "system" }
    taints       = []
    priority     = "Regular"
  }
  application = {
    vm_size      = "Standard_D4s_v3"
    min_count    = 2
    max_count    = 4
    node_count   = 2
    os_disk_size = 100
    labels       = { "pipeshub.ai/node-pool" = "application" }
    taints       = []
    priority     = "Regular"
  }
  data = {
    vm_size      = "Standard_E4s_v3"
    min_count    = 1
    max_count    = 3
    node_count   = 2
    os_disk_size = 200
    labels       = { "pipeshub.ai/node-pool" = "data" }
    taints       = []
    priority     = "Regular"
  }
}

cosmos_db_offer_type = "Standard"
cosmos_db_throughput  = 1000
redis_sku_name       = "Standard"
redis_family         = "C"
redis_capacity       = 1
eventhub_sku         = "Standard"
eventhub_capacity    = 2

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
