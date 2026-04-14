terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.0"
}

provider "aws" {
  region = var.region
}

variable "region" {
  description = "AWS region for resources (set from TABLEFLOW_REGION)"
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket name for WarpStream Tableflow"
  type        = string
  default     = "warpstream-tableflow-demo"
}

variable "create_bucket" {
  description = "Whether to create a new S3 bucket (false to use existing)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project     = "WarpStream Tableflow Demo"
    ManagedBy   = "Terraform"
    Environment = "demo"
  }
}

# Data source for existing bucket (if using existing)
data "aws_s3_bucket" "existing" {
  count  = var.create_bucket ? 0 : 1
  bucket = var.bucket_name
}

# S3 bucket for WarpStream Tableflow data (if creating new)
resource "aws_s3_bucket" "tableflow" {
  count         = var.create_bucket ? 1 : 0
  bucket        = var.bucket_name
  force_destroy = true  # Allow Terraform to delete bucket even if it contains objects

  tags = merge(var.tags, {
    Name = "WarpStream Tableflow Data"
  })
}

# Locals to reference bucket (whether existing or newly created)
locals {
  bucket_id     = var.create_bucket ? aws_s3_bucket.tableflow[0].id : data.aws_s3_bucket.existing[0].id
  bucket_name   = var.create_bucket ? aws_s3_bucket.tableflow[0].bucket : data.aws_s3_bucket.existing[0].bucket
  bucket_arn    = var.create_bucket ? aws_s3_bucket.tableflow[0].arn : data.aws_s3_bucket.existing[0].arn
  bucket_region = var.create_bucket ? aws_s3_bucket.tableflow[0].region : data.aws_s3_bucket.existing[0].region
}

# Enable versioning (only if creating new bucket)
resource "aws_s3_bucket_versioning" "tableflow" {
  count  = var.create_bucket ? 1 : 0
  bucket = local.bucket_id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption (only if creating new bucket)
resource "aws_s3_bucket_server_side_encryption_configuration" "tableflow" {
  count  = var.create_bucket ? 1 : 0
  bucket = local.bucket_id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block public access (only if creating new bucket)
resource "aws_s3_bucket_public_access_block" "tableflow" {
  count  = var.create_bucket ? 1 : 0
  bucket = local.bucket_id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Lifecycle rule for cost optimization (only if creating new bucket)
resource "aws_s3_bucket_lifecycle_configuration" "tableflow" {
  count  = var.create_bucket ? 1 : 0
  bucket = local.bucket_id

  rule {
    id     = "transition-old-data"
    status = "Enabled"

    # Apply to all objects in the bucket
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER_IR"
    }
  }
}

# Outputs
output "bucket_name" {
  description = "S3 bucket name"
  value       = local.bucket_name
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = local.bucket_arn
}

output "bucket_region" {
  description = "S3 bucket region"
  value       = local.bucket_region
}

output "bucket_url" {
  description = "S3 bucket URL for WarpStream"
  value       = "s3://${local.bucket_name}"
}
