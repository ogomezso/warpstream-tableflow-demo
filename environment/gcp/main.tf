terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  description = "GCP project ID"
  type        = string

  validation {
    condition     = var.project_id != "claude-code-prod"
    error_message = "Cannot use production project 'claude-code-prod' for this demo. Please use a development or demo project."
  }
}

variable "region" {
  description = "GCP region for resources (set from TABLEFLOW_REGION)"
  type        = string
}

variable "bucket_name" {
  description = "GCS bucket name for WarpStream Tableflow"
  type        = string
  default     = "warpstream-tableflow-demo"
}

variable "create_bucket" {
  description = "Whether to create a new GCS bucket (false to use existing)"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels to apply to all resources"
  type        = map(string)
  default = {
    project     = "warpstream-tableflow-demo"
    managed_by  = "terraform"
    environment = "demo"
  }
}

# Data source for existing bucket (if using existing)
data "google_storage_bucket" "existing" {
  count = var.create_bucket ? 0 : 1
  name  = var.bucket_name
}

# GCS bucket for WarpStream Tableflow data (if creating new)
resource "google_storage_bucket" "tableflow" {
  count         = var.create_bucket ? 1 : 0
  name          = var.bucket_name
  location      = var.region
  force_destroy = true  # Allow Terraform to delete bucket even if it contains objects

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }

  lifecycle_rule {
    condition {
      age = 30
    }
    action {
      type          = "SetStorageClass"
      storage_class = "NEARLINE"
    }
  }

  lifecycle_rule {
    condition {
      age = 90
    }
    action {
      type          = "SetStorageClass"
      storage_class = "COLDLINE"
    }
  }

  labels = var.labels
}

# Locals to reference bucket (whether existing or newly created)
locals {
  bucket_name      = var.create_bucket ? google_storage_bucket.tableflow[0].name : data.google_storage_bucket.existing[0].name
  bucket_location  = var.create_bucket ? google_storage_bucket.tableflow[0].location : data.google_storage_bucket.existing[0].location
  bucket_self_link = var.create_bucket ? google_storage_bucket.tableflow[0].self_link : data.google_storage_bucket.existing[0].self_link
}

# Outputs
output "bucket_name" {
  description = "GCS bucket name"
  value       = local.bucket_name
}

output "bucket_url" {
  description = "GCS bucket URL for WarpStream"
  value       = "gs://${local.bucket_name}"
}

output "bucket_location" {
  description = "GCS bucket location"
  value       = local.bucket_location
}

output "bucket_self_link" {
  description = "GCS bucket self link"
  value       = local.bucket_self_link
}
