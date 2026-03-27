terraform {
  required_providers {
    warpstream = {
      source  = "warpstreamlabs/warpstream"
      version = "~> 2.7.1"
    }
  }
}

########################################
# Provider + Inputs
########################################

provider "warpstream" {
  token = var.warpstream_api_key
}

variable "warpstream_api_key" {
  description = "WarpStream API token (account key, not agent key)"
  type        = string
  sensitive   = true
}

variable "tableflow_virtual_cluster_id" {
  description = "Virtual cluster ID of the BYOC Tableflow cluster (vci_...)"
  type        = string
}

########################################
# Tableflow pipeline (create + deploy)
########################################

resource "warpstream_pipeline" "tableflow_pipeline" {
  virtual_cluster_id = var.tableflow_virtual_cluster_id
  name               = "orders-tableflow-pipeline"
  state              = "running"
  type               = "tableflow"

  configuration_yaml = file("${path.module}/orders-tableflow-pipeline.yaml")
}

########################################
# Outputs
########################################

output "pipeline_id" {
  value       = warpstream_pipeline.tableflow_pipeline.id
  description = "The ID of the Tableflow pipeline"
}

output "pipeline_name" {
  value       = warpstream_pipeline.tableflow_pipeline.name
  description = "The name of the Tableflow pipeline"
}

output "pipeline_state" {
  value       = warpstream_pipeline.tableflow_pipeline.state
  description = "The state of the Tableflow pipeline"
}