terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
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

########################
# Resources
########################


resource "azurerm_storage_account" "ws" {
  name                     = var.storage_account_name
  resource_group_name      = var.resource_group_name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"

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

resource "azurerm_storage_container" "tableflow" {
  name                  = var.container_name
  storage_account_name  = azurerm_storage_account.ws.name
  container_access_type = "private"
}

########################
# Outputs for Helm / Agents
########################

output "storage_account_name" {
  value       = azurerm_storage_account.ws.name
  description = "Use as AZURE_STORAGE_ACCOUNT in the WarpStream Agents"
}

output "storage_account_primary_access_key" {
  value       = azurerm_storage_account.ws.primary_access_key
  description = "Use as AZURE_STORAGE_KEY in the WarpStream Agents"
  sensitive   = true
}

output "tableflow_container_name" {
  value       = azurerm_storage_container.tableflow.name
  description = "Use in azblob://<container> bucketURL and destination_bucket_url"
}