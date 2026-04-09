# Advanced Queries and Features

This guide covers advanced querying capabilities and Iceberg features available in the demo.

## Table of Contents

- [Advanced Trino Queries](#advanced-trino-queries)
- [Iceberg System Tables](#iceberg-system-tables)
- [Time Travel Queries](#time-travel-queries)
- [Schema Evolution](#schema-evolution)
- [Performance Optimization](#performance-optimization)

## Advanced Trino Queries

### Aggregations and Analytics

```sql
-- Revenue by state (assuming orderunits represents revenue)
SELECT 
  address.state,
  COUNT(*) as total_orders,
  ROUND(SUM(orderunits), 2) as total_revenue,
  ROUND(AVG(orderunits), 2) as avg_order_value,
  ROUND(MIN(orderunits), 2) as min_order,
  ROUND(MAX(orderunits), 2) as max_order
FROM iceberg.default."cp_cluster__datagen-orders"
GROUP BY address.state
ORDER BY total_revenue DESC
LIMIT 10;
```

```sql
-- Orders distribution by hour of day
SELECT 
  hour(ordertime) as order_hour,
  COUNT(*) as order_count
FROM iceberg.default."cp_cluster__datagen-orders"
GROUP BY hour(ordertime)
ORDER BY order_hour;
```

```sql
-- Top items by order volume
SELECT 
  itemid,
  COUNT(*) as times_ordered,
  ROUND(SUM(orderunits), 2) as total_units
FROM iceberg.default."cp_cluster__datagen-orders"
GROUP BY itemid
ORDER BY times_ordered DESC
LIMIT 20;
```

### Window Functions

```sql
-- Running total of orders by state
SELECT 
  address.state,
  ordertime,
  orderunits,
  SUM(orderunits) OVER (
    PARTITION BY address.state 
    ORDER BY ordertime
  ) as running_total
FROM iceberg.default."cp_cluster__datagen-orders"
ORDER BY address.state, ordertime
LIMIT 100;
```

```sql
-- Rank items by order units within each state
SELECT 
  address.state,
  itemid,
  orderunits,
  RANK() OVER (
    PARTITION BY address.state 
    ORDER BY orderunits DESC
  ) as rank_in_state
FROM iceberg.default."cp_cluster__datagen-orders"
QUALIFY rank_in_state <= 5
ORDER BY address.state, rank_in_state;
```

### Complex Filtering

```sql
-- Find unusual order patterns (orders > 2 std deviations from mean)
WITH stats AS (
  SELECT 
    AVG(orderunits) as mean_units,
    STDDEV(orderunits) as std_units
  FROM iceberg.default."cp_cluster__datagen-orders"
)
SELECT 
  o.orderid,
  o.itemid,
  o.orderunits,
  o.address.state,
  ROUND((o.orderunits - s.mean_units) / s.std_units, 2) as z_score
FROM iceberg.default."cp_cluster__datagen-orders" o
CROSS JOIN stats s
WHERE ABS((o.orderunits - s.mean_units) / s.std_units) > 2
ORDER BY z_score DESC
LIMIT 50;
```

## Iceberg System Tables

Iceberg exposes metadata through special system tables. Access them by appending `$<table_name>` to your table name.

### Snapshots Table

View all table snapshots (critical for time travel):

```bash
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT 
    snapshot_id,
    CAST(committed_at AS VARCHAR) as committed_at,
    operation,
    summary['added-records'] as records_added,
    summary['total-records'] as total_records
   FROM iceberg.default.\"cp_cluster__datagen-orders\$snapshots\"
   ORDER BY committed_at DESC
   LIMIT 10"
```

### Files Table

See all data files in the table:

```bash
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT 
    file_path,
    file_format,
    record_count,
    file_size_in_bytes / 1024 / 1024 as size_mb
   FROM iceberg.default.\"cp_cluster__datagen-orders\$files\"
   ORDER BY file_path
   LIMIT 20"
```

### Manifests Table

View manifest files (Iceberg's internal metadata structure):

```bash
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT 
    path,
    length,
    added_data_files_count,
    added_rows_count
   FROM iceberg.default.\"cp_cluster__datagen-orders\$manifests\"
   ORDER BY added_rows_count DESC
   LIMIT 10"
```

### Partitions Table

Show partition statistics (if table is partitioned):

```bash
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT * 
   FROM iceberg.default.\"cp_cluster__datagen-orders\$partitions\"
   LIMIT 10"
```

### History Table

View table evolution history:

```bash
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT 
    CAST(made_current_at AS VARCHAR) as made_current_at,
    snapshot_id,
    is_current_ancestor
   FROM iceberg.default.\"cp_cluster__datagen-orders\$history\"
   ORDER BY made_current_at DESC
   LIMIT 10"
```

## Time Travel Queries

### Using Interactive Tool (Recommended)

```bash
# Launch interactive time travel interface
./demo-query.sh time-travel

# Or use the menu
./demo-query.sh
```

Features:
- 📊 Beautiful formatted tables
- 📈 Total row count before selecting limit
- 📸 Snapshot comparison with statistics
- 🎯 Smart defaults and input validation

### Manual Time Travel

#### Query by Snapshot ID

```bash
# First, get snapshot IDs
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT snapshot_id, CAST(committed_at AS VARCHAR) as committed_at 
   FROM iceberg.default.\"cp_cluster__datagen-orders\$snapshots\"
   ORDER BY committed_at DESC"

# Then query specific snapshot
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT * 
   FROM iceberg.default.\"cp_cluster__datagen-orders\"
   FOR VERSION AS OF 1775740640545456000
   LIMIT 10"
```

#### Query by Timestamp

```bash
# Query table state as of specific timestamp
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT COUNT(*) 
   FROM iceberg.default.\"cp_cluster__datagen-orders\"
   FOR TIMESTAMP AS OF TIMESTAMP '2026-04-09 10:30:00'"
```

#### Compare Snapshots

```bash
# Count records in two different snapshots
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT 
    'snapshot_1' as version,
    COUNT(*) as record_count
   FROM iceberg.default.\"cp_cluster__datagen-orders\"
   FOR VERSION AS OF 1775740640545456000
   UNION ALL
   SELECT 
    'snapshot_2' as version,
    COUNT(*) as record_count
   FROM iceberg.default.\"cp_cluster__datagen-orders\"
   FOR VERSION AS OF 1775740999999999999"
```

#### Find New Records Between Snapshots

```sql
-- Records added between two snapshots
WITH 
  snapshot1 AS (
    SELECT orderid 
    FROM iceberg.default."cp_cluster__datagen-orders"
    FOR VERSION AS OF <older_snapshot_id>
  ),
  snapshot2 AS (
    SELECT orderid 
    FROM iceberg.default."cp_cluster__datagen-orders"
    FOR VERSION AS OF <newer_snapshot_id>
  )
SELECT s2.*
FROM snapshot2 s2
LEFT JOIN snapshot1 s1 ON s2.orderid = s1.orderid
WHERE s1.orderid IS NULL;
```

## Schema Evolution

Iceberg supports schema evolution. Here are examples (note: WarpStream Tableflow manages schema automatically based on Kafka topics):

### View Current Schema

```bash
kubectl exec -n trino deployment/trino -- trino --execute \
  "DESCRIBE iceberg.default.\"cp_cluster__datagen-orders\""
```

### Check Schema Changes Across Snapshots

```bash
# View schema changes in history
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT 
    snapshot_id,
    CAST(committed_at AS VARCHAR) as committed_at,
    operation
   FROM iceberg.default.\"cp_cluster__datagen-orders\$snapshots\"
   WHERE operation = 'replace'
   ORDER BY committed_at DESC"
```

## Performance Optimization

### Query Optimization Tips

1. **Use WHERE clauses** to filter data early:
   ```sql
   SELECT * FROM table WHERE address.state = 'CA'
   ```

2. **Limit result sets** for exploratory queries:
   ```sql
   SELECT * FROM table LIMIT 100
   ```

3. **Leverage column pruning** - only select needed columns:
   ```sql
   SELECT orderid, ordertime FROM table  -- Good
   SELECT * FROM table  -- Avoid for large tables
   ```

4. **Use EXPLAIN** to understand query execution:
   ```bash
   kubectl exec -n trino deployment/trino -- trino --execute \
     "EXPLAIN SELECT * FROM iceberg.default.\"cp_cluster__datagen-orders\" LIMIT 10"
   ```

### File Compaction

Iceberg supports compaction to optimize file sizes. WarpStream Tableflow handles this automatically, but you can monitor file counts:

```bash
# Check number of data files
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT COUNT(*) as file_count,
          SUM(record_count) as total_records,
          ROUND(AVG(file_size_in_bytes) / 1024 / 1024, 2) as avg_file_size_mb
   FROM iceberg.default.\"cp_cluster__datagen-orders\$files\""
```

### Query Performance Monitoring

Use Trino UI to monitor query performance:

1. Open [http://localhost:8080](http://localhost:8080)
2. View recent queries
3. Click on a query to see:
   - Execution timeline
   - Data scanned
   - CPU time
   - Memory usage

## Advanced Use Cases

### Real-time Analytics Dashboard

Combine Trino queries with your favorite BI tool:

```sql
-- Dashboard metrics query
SELECT 
  DATE_TRUNC('hour', ordertime) as hour,
  COUNT(*) as order_count,
  ROUND(SUM(orderunits), 2) as total_revenue,
  COUNT(DISTINCT itemid) as unique_items,
  COUNT(DISTINCT address.state) as states_served
FROM iceberg.default."cp_cluster__datagen-orders"
WHERE ordertime >= CURRENT_TIMESTAMP - INTERVAL '24' HOUR
GROUP BY DATE_TRUNC('hour', ordertime)
ORDER BY hour DESC;
```

### Data Quality Checks

```sql
-- Find potential data quality issues
SELECT 
  'null_orderid' as check_type,
  COUNT(*) as issue_count
FROM iceberg.default."cp_cluster__datagen-orders"
WHERE orderid IS NULL

UNION ALL

SELECT 
  'negative_units' as check_type,
  COUNT(*) as issue_count
FROM iceberg.default."cp_cluster__datagen-orders"
WHERE orderunits < 0

UNION ALL

SELECT 
  'future_orders' as check_type,
  COUNT(*) as issue_count
FROM iceberg.default."cp_cluster__datagen-orders"
WHERE ordertime > CURRENT_TIMESTAMP;
```

## Interactive Trino CLI

For ad-hoc exploration, use the interactive Trino CLI:

```bash
# Start interactive session
kubectl exec -it -n trino deployment/trino -- trino

# Inside Trino CLI:
trino> SHOW CATALOGS;
trino> SHOW SCHEMAS FROM iceberg;
trino> USE iceberg.default;
trino> SHOW TABLES;
trino> DESCRIBE "cp_cluster__datagen-orders";
trino> SELECT COUNT(*) FROM "cp_cluster__datagen-orders";
trino> quit;
```

## See Also

- [README.md](README.md) - Main documentation
- [ARCHITECTURE.md](ARCHITECTURE.md) - Infrastructure details
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Common issues
- [Iceberg Documentation](https://iceberg.apache.org/docs/latest/)
- [Trino Documentation](https://trino.io/docs/current/)
