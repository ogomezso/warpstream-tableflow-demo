# WarpStream Tableflow Demo

End-to-end multi-cloud demo of WarpStream Tableflow with Confluent Platform on Kubernetes. Deploy to **AWS, Azure, or GCP** with cloud-native storage or local MinIO. Includes **Trino query engine** for SQL analytics on Iceberg tables (AWS, GCP, MinIO).

## Quick Links

- 🚀 **[Quick Start (5 minutes)](QUICK_START.md)** - Fast setup with any cloud provider
- 📖 **[Architecture Details](ARCHITECTURE.md)** - Infrastructure and system design  
- 🔧 **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
- 💡 **[Advanced Queries](ADVANCED.md)** - SQL examples and Iceberg features
- 🔀 **[Backend Comparison](BACKEND_OPTIONS.md)** - Compare all storage options

## Overview

**Cloud Providers Supported:**
- ✅ **AWS** - S3 + Trino (native S3 filesystem)
- ✅ **Azure** - ADLS Gen2 (no query engine - URI incompatibility)
- ✅ **GCP** - Cloud Storage + Trino (native GCS filesystem)
- ✅ **Any Provider** - MinIO (local Kubernetes storage)

**What Gets Deployed:**
- **Confluent Platform** (Kafka, Schema Registry, Connect, Control Center)
- **WarpStream Tableflow** (Kafka-to-Iceberg transformation)
- **Cloud Storage** (S3/ADLS Gen2/GCS) or **MinIO** (local)
- **Trino Query Engine** (AWS, GCP, MinIO only)

**Data Flow:**
```
Kafka Connect → Kafka Topic → WarpStream Tableflow → Iceberg Tables → Trino Queries
```

## Supported Configurations

| Cloud | Storage Backend | Trino Support | Best For |
|-------|----------------|---------------|----------|
| **AWS** | S3 (cloud) | ✅ Native S3 | Production (AWS) |
| **AWS** | MinIO (local) | ✅ S3A | Development |
| **Azure** | ADLS Gen2 (cloud) | ❌ No | Production (Azure-only) |
| **Azure** | MinIO (local) | ✅ S3A | Development |
| **GCP** | GCS (cloud) | ✅ Native GCS | Production (GCP) |
| **GCP** | MinIO (local) | ✅ S3A | Development |

See [BACKEND_OPTIONS.md](BACKEND_OPTIONS.md) for detailed comparison.

## Prerequisites

**Need help with setup?** See [QUICK_START.md](QUICK_START.md#setup-prerequisites) for complete instructions including:
- Creating a Kind Kubernetes cluster
- Setting up a WarpStream account
- Generating the Deploy API Key
- Installing all required tools

**Quick checklist:**
- ✅ Kubernetes cluster (Kind, Docker Desktop, EKS, AKS, GKE)
- ✅ `kubectl`, `helm`, `terraform` installed
- ✅ WarpStream account and Deploy API Key
- ✅ Cloud provider CLI authenticated (if using cloud backend):
  - **AWS:** `aws configure` or AWS credentials configured
  - **Azure:** `az login` and `az account set --subscription YOUR_SUBSCRIPTION_ID`
  - **GCP:** `gcloud auth application-default login` and `gcloud config set project YOUR_PROJECT_ID`
  - **MinIO:** No cloud authentication required

## Environment Variables

**Required:**
```bash
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'
```

**Optional:**
```bash
export TABLEFLOW_BACKEND='minio'  # or 'azure' (interactive if not set)
export AZURE_SUBSCRIPTION_ID='...' # Azure backend only
```

For complete variable reference, see [BACKEND_OPTIONS.md](BACKEND_OPTIONS.md#environment-variables-reference).

## Quick Start

### Deploy

```bash
# 1. Set WarpStream API key
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'

# 2. Authenticate with cloud provider (if using cloud backend)
# AWS:
aws configure  # or ensure AWS credentials are set

# Azure:
az login
az account set --subscription YOUR_SUBSCRIPTION_ID

# GCP:
gcloud auth application-default login

# MinIO: No cloud authentication required

# 3. Run the demo
# Option 1: Interactive (recommended - prompts for cloud provider, region, backend)
./demo-startup.sh

# Option 2: Pre-configure (AWS S3 example)
export CLOUD_PROVIDER='aws'
export TABLEFLOW_REGION='us-east-1'
export TABLEFLOW_BACKEND='cloud'
./demo-startup.sh

# Option 3: Pre-configure (GCP GCS example)
export CLOUD_PROVIDER='gcp'
export TABLEFLOW_REGION='us-central1'
export TABLEFLOW_BACKEND='cloud'
./demo-startup.sh

# Option 4: Any cloud + MinIO (local storage, no cloud costs)
export CLOUD_PROVIDER='aws'  # Cluster region
export TABLEFLOW_BACKEND='minio'  # Local storage
./demo-startup.sh
```

**Deployment Flow:**
1. Select cloud provider (AWS, Azure, GCP)
2. Select region (provider-specific list)
3. Select backend (Cloud-native or MinIO)
4. Authenticate (AWS: Confluent employee prompt, Azure: az CLI, GCP: gcloud)
5. Deploy (~5-7 minutes)

### Access UIs

**With Trino (AWS, GCP, MinIO):**
- Confluent Control Center: http://localhost:9021
- Trino UI: http://localhost:8080
- MinIO Console (if MinIO): http://localhost:9001 (minioadmin/minioadmin)

**Azure (no Trino):**
- Confluent Control Center: http://localhost:9021

All UIs are automatically port-forwarded!

### Query Data

```bash
# Show tables (works for AWS S3, GCP GCS, MinIO)
kubectl exec -n trino deployment/trino -- trino --execute \
  'SHOW TABLES FROM iceberg.default'

# Count orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'

# Interactive Trino CLI
kubectl exec -it -n trino deployment/trino -- trino
```

### Time Travel Queries

```bash
# Interactive time travel interface (supports all backends with Trino)
./demo-query.sh time-travel
```

### Cleanup

```bash
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'
./demo-cleanup.sh  # Auto-detects cloud provider and cleans up
```

## Features

### Backend Storage Options

Choose between two backends:

**MinIO (Recommended for Development):**
- ✅ No cloud costs or credentials
- ✅ Built-in Console UI (<http://localhost:9001>)
- ✅ Works with Trino query engine
- ✅ S3-compatible for broad tool support

**Azure ADLS Gen2 (Production):**
- ✅ Enterprise-grade scalability and security
- ✅ Unlimited storage capacity
- ❌ No OSS query engine support (URI incompatibility)

See [BACKEND_OPTIONS.md](BACKEND_OPTIONS.md) for detailed comparison.

### Query Engine (MinIO Only)

**Trino** query engine automatically deployed with MinIO backend:
- SQL analytics on Iceberg tables
- Interactive CLI and Web UI (<http://localhost:8080>)
- Time travel queries via snapshot isolation
- See [ADVANCED.md](ADVANCED.md) for query examples

**Why Trino works with MinIO but not Azure:**
MinIO uses `s3://` URIs (S3-compatible), while Azure uses `azblob://` URIs that Trino/Hadoop cannot read. See [OSS_QUERY_ENGINES.md](OSS_QUERY_ENGINES.md) for technical details.

### Iceberg Time Travel

Interactive tool with snapshot selection and formatted results:

```bash
./demo-query.sh time-travel
```

**Features:**
- Browse available snapshots with timestamps
- Query data as it existed at any snapshot
- Compare snapshot vs current data with statistics
- Formatted table output for easy reading

For manual queries and advanced examples, see [ADVANCED.md](ADVANCED.md#time-travel-queries).

## Troubleshooting

For detailed troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).

**Common Issues:**

```bash
# Cloud authentication errors
# Azure:
az login
az account set --subscription YOUR_SUBSCRIPTION_ID

# AWS:
aws configure

# GCP:
gcloud auth application-default login

# Port-forwards died
pkill -f "port-forward"
./demo-startup.sh  # Will skip deployment, just restart port-forwards

# Namespace stuck terminating
kubectl get all -n <namespace>
```

## Project Structure

See [ARCHITECTURE.md](ARCHITECTURE.md#project-structure) for complete directory tree.

**Key files:**
- `demo-startup.sh` - Main setup script
- `demo-cleanup.sh` - Cleanup script  
- `demo-query.sh` - Unified query interface
- `environment/` - Kubernetes manifests and Terraform configs
