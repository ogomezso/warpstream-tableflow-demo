# Trino with WarpStream Tableflow on MinIO

## ✅ Status: WORKS

Trino **can successfully query WarpStream Tableflow tables** on MinIO using Hadoop's S3A filesystem.

## How It Works

WarpStream writes `s3://` URIs in Iceberg metadata when using MinIO, which are fully compatible with Hadoop's S3A filesystem implementation.

## Configuration

### Key Settings

**Catalog Properties (`iceberg.properties`):**
```properties
connector.name=iceberg
iceberg.catalog.type=rest
iceberg.rest-catalog.uri=http://warpstream-iceberg-proxy.trino.svc.cluster.local:8080/catalogs/iceberg/<VCI>
iceberg.rest-catalog.vended-credentials-enabled=true
fs.native-s3.enabled=false  # Use S3A instead of native S3
```

**Hadoop Configuration (`core-site.xml`):**
```xml
<configuration>
  <property>
    <name>fs.s3a.endpoint</name>
    <value>http://minio.minio.svc.cluster.local:9000</value>
  </property>
  <property>
    <name>fs.s3a.access.key</name>
    <value>minioadmin</value>
  </property>
  <property>
    <name>fs.s3a.secret.key</name>
    <value>minioadmin</value>
  </property>
  <property>
    <name>fs.s3a.path.style.access</name>
    <value>true</value>
  </property>
  <property>
    <name>fs.s3a.connection.ssl.enabled</name>
    <value>false</value>
  </property>
</configuration>
```

## Deployment

```bash
cd environment/trino
./deploy-minio.sh
```

## Testing

### What Works ✅

All Iceberg operations work successfully:

```bash
# Show catalogs
kubectl exec -n trino deployment/trino -- trino --execute "SHOW CATALOGS"

# Show schemas
kubectl exec -n trino deployment/trino -- trino --execute "SHOW SCHEMAS FROM iceberg"

# Show tables
kubectl exec -n trino deployment/trino -- trino --execute "SHOW TABLES FROM iceberg.default"

# Describe table
kubectl exec -n trino deployment/trino -- trino --execute "DESCRIBE iceberg.default.\"cp_cluster__datagen-orders\""

# Count rows
kubectl exec -n trino deployment/trino -- trino --execute "SELECT COUNT(*) FROM iceberg.default.\"cp_cluster__datagen-orders\""

# Select data
kubectl exec -n trino deployment/trino -- trino --execute "SELECT orderid, itemid, address.city FROM iceberg.default.\"cp_cluster__datagen-orders\" LIMIT 10"

# Aggregations
kubectl exec -n trino deployment/trino -- trino --execute "SELECT address.state, COUNT(*) FROM iceberg.default.\"cp_cluster__datagen-orders\" GROUP BY address.state ORDER BY COUNT(*) DESC LIMIT 10"
```

## Architecture

```
┌─────────┐         ┌──────────────────┐         ┌──────────────┐
│  Trino  │ ──────> │  Nginx Proxy     │ ──────> │  WarpStream  │
│         │         │  (injects auth)  │         │  REST Catalog│
└────┬────┘         └──────────────────┘         └──────────────┘
     │                                                   │
     │ (Hadoop S3A)                                      │
     v                                                   v
┌──────────────────────────────────────────────────────────────┐
│  MinIO S3-Compatible Storage                                 │
│  s3://tableflow/warpstream/_tableflow/...                    │
│  ✅ Trino reads via S3A FileSystem                          │
└──────────────────────────────────────────────────────────────┘
```

## Key Differences from Azure Setup

| Aspect | MinIO | Azure |
|--------|-------|-------|
| URI Scheme | `s3://` | `azblob://` |
| Trino Compatibility | ✅ Works | ❌ Fails |
| Filesystem | Hadoop S3A | Not supported |
| Setup Complexity | Simple | Complex (proxy required) |
| Query Performance | Good | N/A (doesn't work) |

## Performance Notes

- First query may be slower as Trino fetches and caches Iceberg metadata
- Subsequent queries benefit from metadata caching
- S3A connection pooling improves performance for concurrent queries
- Configure `fs.s3a.connection.maximum` for tuning connection pool size

## Files

- `k8s/configmap-minio.yaml` - Trino configuration with S3A settings
- `k8s/deployment-minio.yaml` - Trino deployment with MinIO credentials
- `deploy-minio.sh` - Automated deployment script
- `k8s/proxy-*.yaml` - HTTP proxy to inject WarpStream auth header

## Comparison with Azure

See [README.md](./README.md) for details on why Trino doesn't work with Azure's `azblob://` URIs but works perfectly with MinIO's `s3://` URIs.
