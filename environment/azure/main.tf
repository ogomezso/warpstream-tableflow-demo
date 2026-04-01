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
  description = "Azure region for the storage account"
  type        = string
  default     = "westeurope"
}

variable "resource_group_name" {
  description = "Name of the resource group"
  type        = string
  default     = "ogomezso-se"
}

variable "storage_account_name" {
  description = "Globally-unique storage account name (3-24 lower-case letters and numbers)"
  type        = string
  default     = "wsdemostore"
}

variable "container_name" {
  description = "Blob container name for WarpStream/Tableflow"
  type        = string
  default     = "tableflow"
}

variable "create_storage_account" {
  description = "Whether to create a new storage account (false to use existing)"
  type        = bool
  default     = true
}

########################
# Data Sources
########################

# Try to fetch existing storage account
data "azurerm_storage_account" "existing" {
  count               = var.create_storage_account ? 0 : 1
  name                = var.storage_account_name
  resource_group_name = var.resource_group_name
}

########################
# Resources
########################


resource "azurerm_storage_account" "ws" {
  count                = var.create_storage_account ? 1 : 0
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
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

# Local to reference the storage account (whether existing or newly created)
locals {
  storage_account_id   = var.create_storage_account ? azurerm_storage_account.ws[0].id : data.azurerm_storage_account.existing[0].id
  storage_account_name = var.create_storage_account ? azurerm_storage_account.ws[0].name : data.azurerm_storage_account.existing[0].name
  storage_account_key  = var.create_storage_account ? azurerm_storage_account.ws[0].primary_access_key : data.azurerm_storage_account.existing[0].primary_access_key
}

resource "azurerm_storage_data_lake_gen2_filesystem" "tableflow" {
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
  value       = azurerm_storage_data_lake_gen2_filesystem.tableflow.name
  description = "Use in abfss://<container>@<account>.dfs.core.windows.net/ for ADLS Gen2"
}