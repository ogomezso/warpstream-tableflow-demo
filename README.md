# WarpStream Tableflow Demo

End-to-end demo of WarpStream Tableflow with Confluent Platform on Kubernetes. Supports two storage backends: Azure ADLS Gen2 (cloud) or MinIO (local). MinIO backend includes Trino query engine for SQL analytics on Iceberg tables.

## Quick Links

- 🚀 **[Quick Start (5 minutes)](QUICK_START.md)** - Fast setup with MinIO + Trino
- 📖 **[Architecture Details](ARCHITECTURE.md)** - Infrastructure and system design
- 🔧 **[Troubleshooting](TROUBLESHOOTING.md)** - Common issues and solutions
- 💡 **[Advanced Queries](ADVANCED.md)** - SQL examples and Iceberg features
- 🔀 **[Backend Comparison](BACKEND_OPTIONS.md)** - Azure vs MinIO details

## Overview

This demo deploys:
- **Confluent Platform** (Kafka, Schema Registry, Connect, Control Center)
- **WarpStream Tableflow** (Kafka-to-Iceberg transformation)
- **Backend Storage** (Azure ADLS Gen2 or MinIO)
- **Query Engine** (Trino with Iceberg connector - MinIO only)

**Data Flow:**
```
Kafka Connect (datagen) → Kafka Topic → WarpStream Tableflow → Iceberg Tables → Trino Queries
```

## Architecture

### MinIO Backend (Recommended for Development)

```
┌────────────────────────────────────┐
│  Kubernetes Cluster                │
│                                    │
│  ┌──────────────┐  ┌────────────┐ │
│  │ WarpStream ──┼─►│   MinIO    │ │
│  │   Agent      │  │  (S3-API)  │ │
│  └──────────────┘  └─────▲──────┘ │
│                          │         │
│  ┌──────────────────────┼──────┐  │
│  │       Trino (S3A)    │      │  │
│  └──────────────────────┘      │  │
└────────────────────────────────────┘
```

**Why MinIO?**
- ✅ No cloud costs - runs in Kubernetes
- ✅ Works with Trino/Spark (S3-compatible)
- ✅ Built-in Console UI
- ✅ Perfect for development and demos

### Azure ADLS Gen2 Backend (Production)

```
┌──────────────┐     ┌──────────────────┐
│  Kubernetes  │     │  Azure Cloud     │
│              │     │                  │
│  WarpStream ────►  │  ADLS Gen2       │
│  Agent       │     │  Storage Account │
└──────────────┘     └──────────────────┘
```

**Why Azure?**
- ✅ Production-ready scalability
- ✅ Enterprise security and compliance
- ✅ Unlimited storage
- ❌ No OSS query engine support (azblob:// vs s3://)

See [BACKEND_OPTIONS.md](BACKEND_OPTIONS.md) for detailed comparison.

## Prerequisites

**Required:**
- Kubernetes cluster with `kubectl` access
- `helm` (v3+), `terraform`
- WarpStream account ([console.warpstream.com](https://console.warpstream.com))

**Optional (Azure backend only):**
- Azure subscription
- `az` CLI

**WarpStream Deploy API Key:**
1. Login to [WarpStream Console](https://console.warpstream.com)
2. Navigate to **Settings** > **API Keys**
3. Create **Account API Key** (NOT agent key - those start with `aki_`)
4. Copy the key for `WARPSTREAM_DEPLOY_API_KEY`

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
# Set API key
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'

# Option 1: MinIO backend (recommended for demos)
export TABLEFLOW_BACKEND='minio'
./demo-startup.sh

# Option 2: Azure backend
export TABLEFLOW_BACKEND='azure'
./demo-startup.sh

# Option 3: Interactive (will prompt for backend choice)
./demo-startup.sh
```

Deployment takes ~5-7 minutes. All UIs are automatically port-forwarded!

### Access UIs

**MinIO Backend:**
- Confluent Control Center: http://localhost:9021
- MinIO Console: http://localhost:9001 (minioadmin/minioadmin)
- Trino UI: http://localhost:8080

**Azure Backend:**
- Confluent Control Center: http://localhost:9021

### Query Data (MinIO Backend)

```bash
# Show tables
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
# Interactive time travel interface
./demo-query.sh time-travel

# Or use menu
./demo-query.sh
```

### Cleanup

```bash
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'
./demo-cleanup.sh
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
# Azure authentication
az logout && az login

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
