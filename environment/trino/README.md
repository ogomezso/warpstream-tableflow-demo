# Trino with WarpStream Tableflow

## ⚠️ Status: DOES NOT WORK

Trino **cannot query WarpStream Tableflow tables** on Azure due to URI format incompatibility.

## The Problem

WarpStream writes `azblob://` URIs in Iceberg metadata, but Trino's Hadoop FileSystem only supports:
- `s3://`, `s3a://` (AWS)
- `gs://` (GCP)
- `abfs://`, `wasb://` (Azure)
- `hdfs://`, `file://`

**No support for `azblob://` exists in Hadoop.**

## What We Implemented

### 1. HTTP Proxy Solution
Created an nginx-based proxy to inject WarpStream `Authorization: Bearer <AgentKey>` header, following WarpStream's guidance.

### 2. Attempted Workarounds
- Mapped `azblob://` scheme to ABFS in Hadoop config (failed - wrong URL structure)
- Configured ABFS support for Azure storage (works for `abfs://` but metadata has `azblob://`)
- Proper JSON error responses for 404s (fixed Iceberg REST client errors)

## Test Results

### ✅ What Works
- REST catalog connectivity via proxy
- `SHOW CATALOGS` - Lists catalogs
- `SHOW SCHEMAS FROM iceberg` - Lists schemas  
- `SHOW TABLES FROM iceberg.default` - Lists tables
- `DESCRIBE table` - Shows table schema
- Table metadata loads successfully (200 OK)

### ❌ What Fails
- `SELECT * FROM table` - Cannot read data files
- `SELECT COUNT(*) FROM table` - Cannot read data files
- Any query that accesses actual Parquet files

### Error Message
```
Query failed: No factory for location: azblob://tableflow/warpstream/_tableflow/cp_cluster__datagen-orders-.../data/file.parquet
```

## Deployment (For Testing Only)

```bash
cd environment/trino
./deploy.sh
```

## Testing

```bash
# What works
kubectl exec -n trino deployment/trino -- trino --execute "SHOW CATALOGS"
kubectl exec -n trino deployment/trino -- trino --execute "SHOW TABLES FROM iceberg.default"
kubectl exec -n trino deployment/trino -- trino --execute "DESCRIBE iceberg.default.\"cp_cluster__datagen-orders\""

# What fails
kubectl exec -n trino deployment/trino -- trino --execute "SELECT COUNT(*) FROM iceberg.default.\"cp_cluster__datagen-orders\""
```

## Architecture

```
┌─────────┐         ┌──────────────────┐         ┌──────────────┐
│  Trino  │ ──────> │  Nginx Proxy     │ ──────> │  WarpStream  │
│         │         │  (injects auth)  │         │  REST Catalog│
└─────────┘         └──────────────────┘         └──────────────┘
     │                                                   │
     │                                                   │
     v                                                   v
┌──────────────────────────────────────────────────────────────┐
│  Azure Blob Storage                                          │
│  azblob://tableflow/warpstream/_tableflow/...                │
│  ❌ Trino cannot read (No FileSystem for azblob://)         │
└──────────────────────────────────────────────────────────────┘
```

## Conclusion

The HTTP proxy successfully handles authentication, but Trino still cannot query data due to the `azblob://` URI format in Iceberg metadata.

**Recommendation:** Use Apache Spark or request WarpStream to support `abfs://` URIs.

## Files

- `k8s/namespace.yaml` - Trino namespace
- `k8s/configmap.yaml` - Trino configuration with Iceberg REST catalog
- `k8s/deployment.yaml` - Trino deployment
- `k8s/service.yaml` - Trino service
- `k8s/proxy-*.yaml` - HTTP proxy to inject WarpStream auth header
- `deploy.sh` - Deployment script

## See Also

- [OSS_QUERY_ENGINES.md](../../OSS_QUERY_ENGINES.md) - Detailed test results
- [QUERY_ENGINE_SUMMARY.md](../../QUERY_ENGINE_SUMMARY.md) - Summary of all engines tested
