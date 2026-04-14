terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.66"
    }
  }
}

provider "azurerm" {
  features {}
}

########################
# Variables
########################

variable "location" {
  description = "Azure region for the storage account (set from TABLEFLOW_REGION)"
  type        = string
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "warpstream-tableflow-demo"
}

variable "create_resource_group" {
  description = "Whether to create a new resource group (false to use existing)"
  type        = bool
  default     = true
}

variable "owner_email" {
  description = "Owner email tag (required by Azure policy when creating resource group)"
  type        = string
  default     = ""
}

variable "storage_account_name" {
  description = "Globally-unique storage account name (3-24 lower-case letters and numbers)"
  type        = string
  default     = "wstableflowdemo"
}

variable "create_storage_account" {
  description = "Whether to create a new storage account (false to use existing)"
  type        = bool
  default     = true
}

variable "container_name" {
  description = "Blob container name for WarpStream/Tableflow"
  type        = string
  default     = "tableflow"
}

variable "create_container" {
  description = "Whether to create a new container (false to use existing)"
  type        = bool
  default     = true
}

########################
# Data Sources
########################

# Fetch existing resource group (if using existing)
data "azurerm_resource_group" "existing" {
  count = var.create_resource_group ? 0 : 1
  name  = var.resource_group_name
}

# Try to fetch existing storage account (if using existing)
data "azurerm_storage_account" "existing" {
  count               = var.create_storage_account ? 0 : 1
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

########################
# Resources
########################

# Create resource group (if not using existing)
resource "azurerm_resource_group" "ws" {
  count    = var.create_resource_group ? 1 : 0
  name     = var.resource_group_name
  location = var.location

  tags = merge(
    {
      environment = "warpstream-tableflow-demo"
    },
    var.owner_email != "" ? {
      owner_email = var.owner_email
    } : {}
  )

  lifecycle {
    prevent_destroy = false  # Allow destroy only if we created it
  }
}

# Local to reference the resource group (whether existing or newly created)
locals {
  resource_group_name = var.create_resource_group ? azurerm_resource_group.ws[0].name : data.azurerm_resource_group.existing[0].name
  location            = var.create_resource_group ? azurerm_resource_group.ws[0].location : data.azurerm_resource_group.existing[0].location
}

resource "azurerm_storage_account" "ws" {
  count                = var.create_storage_account ? 1 : 0
  name                     = var.storage_account_name
  resource_group_name      = local.resource_group_name
  location                 = local.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  is_hns_enabled           = true

  allow_nested_items_to_be_public = false

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  tags = {
    environment = "warpstream-tableflow-demo"
  }
}

# Locals to reference resources (whether existing or newly created)
locals {
  storage_account_id   = var.create_storage_account ? azurerm_storage_account.ws[0].id : data.azurerm_storage_account.existing[0].id
  storage_account_name = var.create_storage_account ? azurerm_storage_account.ws[0].name : data.azurerm_storage_account.existing[0].name
  storage_account_key  = var.create_storage_account ? azurerm_storage_account.ws[0].primary_access_key : data.azurerm_storage_account.existing[0].primary_access_key
  # For container, just use the variable name directly (no data source available for ADLS Gen2 filesystem)
  container_name       = var.create_container ? azurerm_storage_data_lake_gen2_filesystem.tableflow[0].name : var.container_name
}

resource "azurerm_storage_data_lake_gen2_filesystem" "tableflow" {
  count              = var.create_container ? 1 : 0
  name               = var.container_name
  storage_account_id = local.storage_account_id
}

########################
# Outputs for Helm / Agents
########################

output "storage_account_name" {
  value       = local.storage_account_name
  description = "Use as AZURE_STORAGE_ACCOUNT in the WarpStream Agents"
}

output "storage_account_primary_access_key" {
  value       = local.storage_account_key
  description = "Use as AZURE_STORAGE_KEY in the WarpStream Agents"
  sensitive   = true
}

output "tableflow_container_name" {
  value       = local.container_name
  description = "Use in abfss://<container>@<account>.dfs.core.windows.net/ for ADLS Gen2"
}