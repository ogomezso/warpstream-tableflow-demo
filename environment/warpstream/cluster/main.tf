terraform {
  required_providers {
    warpstream = {
      source  = "warpstreamlabs/warpstream"
      version = "~> 2.7.1"
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

variable "cloud_provider" {
  description = "Cloud provider for WarpStream Tableflow cluster (aws, azure, gcp)"
  type        = string
  default     = "azure"
}

variable "cloud_region" {
  description = "Cloud region for WarpStream Tableflow cluster"
  type        = string
  default     = "eastus"
}

resource "warpstream_tableflow_cluster" "dev_cluster" {
  name = "vcn_dl_tableflow_cluster_dev"
  tier = "dev"
  cloud = {
    provider = var.cloud_provider
    region   = var.cloud_region
  }
}
resource "warpstream_agent_key" "demo_agent_key" {
  virtual_cluster_id = warpstream_tableflow_cluster.dev_cluster.id
  name               = "akn_tableflow_demo_agent_key"
}
output "tableflow_virtual_cluster_id" {
  value = warpstream_tableflow_cluster.dev_cluster.id
}

output "tableflow_agent_key" {
  value     = warpstream_agent_key.demo_agent_key.key
  sensitive = true
}