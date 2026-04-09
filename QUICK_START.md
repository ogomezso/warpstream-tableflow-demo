# Quick Start Guide - MinIO Backend with Trino

This guide gets you started with the MinIO backend and Trino query engine in under 5 minutes.

## Prerequisites

```bash
# Required tools
kubectl version
helm version  
terraform version

# Required environment variable
export WARPSTREAM_DEPLOY_API_KEY='your_warpstream_account_api_key'
```

## Deploy

```bash
# Option 1: Pre-select MinIO backend
export TABLEFLOW_BACKEND='minio'
./demo-startup.sh

# Option 2: Interactive selection (choose option 2)
./demo-startup.sh
```

Deployment takes ~5-7 minutes. All port-forwards are set up automatically!

## Access UIs

Once deployment completes, these URLs are immediately available:

| UI | URL | Credentials | Purpose |
|----|-----|-------------|---------|
| **Confluent Control Center** | <http://localhost:9021> | - | Monitor Kafka topics and connectors |
| **MinIO Console** | <http://localhost:9001> | minioadmin / minioadmin | Browse Iceberg tables and Parquet files |
| **Trino Query UI** | <http://localhost:8080> | - | View query history and metrics |

> **Note**: All UIs are automatically port-forwarded - just click the links!

## Query Data with Trino

### Quick Queries (Copy & Paste)

```bash
# Show available tables
kubectl exec -n trino deployment/trino -- trino --execute \
  'SHOW TABLES FROM iceberg.default'

# Count total orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'

# View sample orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT orderid, itemid, orderunits, address.city, address.state 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   LIMIT 10'

# Top 5 states by order count
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT address.state, COUNT(*) as orders 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   GROUP BY address.state 
   ORDER BY orders DESC 
   LIMIT 5'

# Average order units by state
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT address.state, 
          ROUND(AVG(orderunits), 2) as avg_units,
          COUNT(*) as order_count
   FROM iceberg.default."cp_cluster__datagen-orders" 
   GROUP BY address.state 
   ORDER BY avg_units DESC 
   LIMIT 10'
```

### Interactive Trino CLI

```bash
# Start interactive SQL shell
kubectl exec -it -n trino deployment/trino -- trino

# Then run queries interactively:
trino> SHOW SCHEMAS FROM iceberg;
trino> USE iceberg.default;
trino> DESCRIBE "cp_cluster__datagen-orders";
trino> SELECT * FROM "cp_cluster__datagen-orders" LIMIT 5;
trino> quit;
```

## Verify Data Flow

### 1. Check Confluent Control Center

Open <http://localhost:9021>:
- Navigate to **Topics** → `datagen-orders`
- See messages flowing in real-time
- Check **Connect** → Connectors → `datagen-orders`

### 2. Check MinIO Console

Open <http://localhost:9001> (login: minioadmin/minioadmin):
- Navigate to **Buckets** → `tableflow` → `warpstream/_tableflow/`
- See Iceberg table directory: `cp_cluster__datagen-orders-<uuid>`
- Browse `data/` folder for Parquet files
- Browse `metadata/` folder for Iceberg metadata

### 3. Check Trino UI

Open <http://localhost:8080>:
- View recent queries in the dashboard
- Click on a query to see execution details
- Check query performance and data scanned

## Example Workflow

```bash
# 1. Check how many orders are in the system
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'
# Output: 12769 (or similar)

# 2. Wait 30 seconds for more data to flow in
sleep 30

# 3. Check again - should see more orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'
# Output: Higher number

# 4. Analyze the latest orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT orderid, itemid, address.state, orderunits 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   ORDER BY ordertime DESC 
   LIMIT 10'
```

## Advanced Queries

```bash
# Find high-value orders (> 8 units)
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT orderid, itemid, orderunits, address.state 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   WHERE orderunits > 8.0 
   ORDER BY orderunits DESC 
   LIMIT 20'

# Orders by city and state
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT address.city, address.state, COUNT(*) as orders 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   GROUP BY address.city, address.state 
   ORDER BY orders DESC 
   LIMIT 20'

# Distribution of order sizes
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT 
     CASE 
       WHEN orderunits < 2 THEN "Small (0-2)"
       WHEN orderunits < 5 THEN "Medium (2-5)"
       WHEN orderunits < 8 THEN "Large (5-8)"
       ELSE "XLarge (8+)"
     END as order_size,
     COUNT(*) as count
   FROM iceberg.default."cp_cluster__datagen-orders"
   GROUP BY 1
   ORDER BY count DESC'
```

## Cleanup

```bash
export WARPSTREAM_DEPLOY_API_KEY='your_warpstream_account_api_key'
./demo-cleanup.sh
```

Cleanup automatically stops all port-forwards and removes all resources.

## Troubleshooting

### Port-forwards not working?

```bash
# Check if port-forwards are running
ps aux | grep "port-forward"

# Manually restart if needed
pkill -f "port-forward"
./demo-startup.sh  # Will skip deployment, just setup port-forwards
```

### Trino query failing?

```bash
# Check Trino pod status
kubectl get pods -n trino

# Check Trino logs
kubectl logs -n trino deployment/trino --tail=50

# Verify MinIO connectivity
kubectl exec -n trino deployment/trino -- curl -s http://minio.minio.svc.cluster.local:9000
```

### No data in tables?

```bash
# Check WarpStream agent
kubectl get pods -n warpstream
kubectl logs -n warpstream deployment/warpstream-agent --tail=50

# Check Tableflow pipeline
kubectl get pipelines -n warpstream
```

## Time Travel Queries

Iceberg's snapshot isolation enables querying historical data:

```bash
# Unified query interface (recommended)
./demo-query.sh time-travel

# Or use interactive menu
./demo-query.sh
```

**Features:**
- 📊 **Beautiful table formatting** - Easy-to-read aligned columns
- 📈 **Total row count shown** - Know how many rows before selecting limit
- 📸 **Snapshot comparison** - See changes between snapshots with percentages
- 🎯 **Smart defaults** - Automatic capping at max available rows

The script will:
1. Show all available snapshots with timestamps
2. Display total row count in selected snapshot
3. Let you choose how many rows to view
4. Show data in formatted table
5. Compare snapshot vs current with statistics

**Manual time travel:**
```bash
# Query by snapshot ID
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT * FROM iceberg.default.\"cp_cluster__datagen-orders\" 
   FOR VERSION AS OF 1775740640545456000 
   LIMIT 10"

# View all snapshots
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT snapshot_id, committed_at 
   FROM iceberg.default.\"cp_cluster__datagen-orders\$snapshots\"
   ORDER BY committed_at DESC"
```

See [README.md](README.md#time-travel-queries) for more examples.

## What's Next?

- Explore the [full README](README.md) for detailed documentation
- Check [BACKEND_OPTIONS.md](BACKEND_OPTIONS.md) for backend comparison
- See [environment/trino/README-MINIO.md](environment/trino/README-MINIO.md) for Trino architecture
- Review [OSS_QUERY_ENGINES.md](OSS_QUERY_ENGINES.md) for why Trino works with MinIO but not Azure

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│                                                             │
│  ┌──────────────┐  ┌──────────┐  ┌───────────┐            │
│  │  Confluent   │  │ WarpStream│  │   MinIO   │            │
│  │   Platform   │→ │   Agent   │→ │  Storage  │            │
│  │   (Kafka)    │  │ +Pipeline │  │(Tableflow)│            │
│  └──────────────┘  └──────────┘  └─────↑─────┘            │
│         ↓                                │                  │
│  ┌──────────────────────────────────────┴──────┐           │
│  │           Trino Query Engine                │           │
│  │     (Queries Iceberg via S3A)               │           │
│  └─────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘

Data Flow:
1. Kafka Connect generates orders → datagen-orders topic
2. WarpStream Tableflow pipeline transforms → Iceberg tables
3. Iceberg tables stored in MinIO (S3-compatible)
4. Trino queries Iceberg tables via Hadoop S3A
```

---

**🎉 You're all set!** Start querying your Iceberg tables with Trino!
