terraform {
  required_providers {
    warpstream = {
      source  = "warpstreamlabs/warpstream"
      version = "~> 2.6.0"
    }
  }
}

provider "warpstream" {
  token = var.warpstream_api_key
}

variable "warpstream_api_key" {
  type      = string
  sensitive = true
}

resource "warpstream_tableflow_cluster" "dev_cluster" {
  name = "vcn_dl_tableflow_cluster_dev"
  tier = "dev"
  cloud = {
    provider = "azure"
    region   = "eastus"
  }
}
resource "warpstream_agent_key" "demo_agent_key" {
  virtual_cluster_id = warpstream_tableflow_cluster.dev_cluster.id
  name               = "akn_tableflow_demo_agent_key"
}

# resource "warpstream_pipeline" "tableflow_pipeline" {
#   virtual_cluster_id = warpstream_tableflow_cluster.dev_cluster.id
#   name               = "tableflow_demo_pipeline"
#   state              = "running"
#   type               = "tableflow"
#   configuration_yaml = <<EOT
# source_clusters:
#   - name: kafka_cluster_1
#     bootstrap_brokers:
#       - hostname: YOUR_KAFKA_HOSTNAME
#         port: 9092
# tables:
#     - source_cluster_name: kafka_cluster_1
#       source_topic: logs
#       source_format: json
#       schema_mode: inline
#       schema:
#         fields:
#           - { name: environment, type: string, id: 1}
#           - { name: service, type: string, id: 2}
#           - { name: status, type: string, id: 3}
#           - { name: message, type: string, id: 4}
# destination_bucket_url: s3://tableflow-bucket?region=us-east-1
#   EOT
# }

output "tableflow_virtual_cluster_id" {
  value = warpstream_tableflow_cluster.dev_cluster.id
}

output "tableflow_agent_key" {
  value     = warpstream_agent_key.demo_agent_key.key
  sensitive = true
}