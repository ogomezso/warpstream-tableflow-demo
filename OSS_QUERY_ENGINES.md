# Query Engine Testing with WarpStream Tableflow on Azure

## Executive Summary

**Problem:** WarpStream Tableflow writes `azblob://` URIs in Iceberg metadata, which are incompatible with Hadoop FileSystem used by most query engines.

**Engines Tested:** Trino, Spark  
**Result:** Both FAILED with identical error - `No FileSystem for scheme "azblob"`  
**Root Cause:** URI format mismatch between Azure Go SDK (`azblob://`) and Hadoop ABFS (`abfss://`)

---

## Test Environment

### Infrastructure Created

```
environment/
├── trino/
│   ├── k8s/
│   │   ├── namespace.yaml              # Trino namespace
│   │   ├── configmap.yaml              # Trino config + Iceberg catalog
│   │   ├── deployment.yaml             # Trino deployment
│   │   ├── service.yaml                # Trino service
│   │   ├── proxy-configmap.yaml        # HTTP proxy for WarpStream auth
│   │   ├── proxy-deployment.yaml       # Proxy deployment
│   │   └── proxy-service.yaml          # Proxy service
│   ├── deploy.sh                       # Automated deployment script
│   ├── test.sh                         # Comprehensive test script (7 tests)
│   └── README.md                       # Documentation
│
└── spark/
    ├── k8s/
    │   ├── namespace.yaml              # Spark namespace
    │   ├── configmap.yaml              # Spark config + Iceberg catalog
    │   ├── deployment.yaml             # Spark deployment with init containers
    │   └── service.yaml                # Spark service
    ├── deploy.sh                       # Automated deployment script
    └── test.sh                         # Comprehensive test script (5 tests)
```

### WarpStream Configuration

- **Virtual Cluster ID:** `vci_dl_d857ed96_bbbc_4289_8e06_75c77dcbfe12`
- **REST Catalog URI:** `https://metadata.default.eastus.azure.warpstream.com/catalogs/iceberg/<VCI>`
- **Storage Account:** `wsdemostore`
- **Container:** `tableflow`
- **Table:** `cp_cluster__datagen-orders`

---

## 1. Apache Trino Testing

### Version & Components

- **Trino:** 469
- **Iceberg Connector:** Built-in
- **HTTP Proxy:** nginx:alpine (for WarpStream authentication)
- **Test Date:** 2026-04-01

### Infrastructure Deployed

#### 1. HTTP Proxy (nginx)

**Purpose:** Inject WarpStream `Authorization: Bearer <AgentKey>` header

**Configuration:**
```nginx
location / {
    proxy_pass https://metadata.default.eastus.azure.warpstream.com;
    proxy_set_header Authorization "Bearer ${WARPSTREAM_AGENT_KEY}";
    proxy_set_header Host metadata.default.eastus.azure.warpstream.com;
    proxy_intercept_errors on;
    error_page 404 = @handle_404;
}

# Return proper JSON for 404s (Iceberg REST spec)
location @handle_404 {
    default_type application/json;
    return 404 '{"error":{"message":"Resource not found","type":"NotFoundException","code":404}}';
}
```

**Why needed:** Trino's Iceberg REST catalog doesn't have a simple "static Bearer token" option, so we proxy requests to inject the header.

#### 2. Trino Configuration

**Iceberg Catalog (`iceberg.properties`):**
```properties
connector.name=iceberg
iceberg.catalog.type=rest
iceberg.rest-catalog.uri=http://warpstream-iceberg-proxy.trino.svc.cluster.local:8080/catalogs/iceberg/vci_dl_d857ed96_bbbc_4289_8e06_75c77dcbfe12
```

**Hadoop Core Site (`core-site.xml`):**
```xml
<configuration>
  <!-- Attempted azblob:// mapping (FAILED) -->
  <property>
    <name>fs.azblob.impl</name>
    <value>org.apache.hadoop.fs.azurebfs.AzureBlobFileSystem</value>
  </property>
  
  <!-- ABFS support -->
  <property>
    <name>fs.abfs.impl</name>
    <value>org.apache.hadoop.fs.azurebfs.AzureBlobFileSystem</value>
  </property>
  <property>
    <name>fs.abfss.impl</name>
    <value>org.apache.hadoop.fs.azurebfs.SecureAzureBlobFileSystem</value>
  </property>
  
  <!-- Azure storage authentication -->
  <property>
    <name>fs.azure.account.key.wsdemostore.dfs.core.windows.net</name>
    <value>${env.AZURE_STORAGE_KEY}</value>
  </property>
</configuration>
```

### Tests Performed

#### Test 1: Catalog Connectivity
```sql
SHOW CATALOGS;
```
**Result:** ✅ **SUCCESS**  
**Output:** `iceberg`, `jmx`, `memory`, `system`, `tpcds`, `tpch`

#### Test 2: Schema Discovery
```sql
SHOW SCHEMAS FROM iceberg;
```
**Result:** ✅ **SUCCESS**  
**Output:** `default`, `information_schema`

#### Test 3: Table Discovery
```sql
SHOW TABLES FROM iceberg.default;
```
**Result:** ✅ **SUCCESS**  
**Output:** `cp_cluster__datagen-orders`

#### Test 4: Table Metadata
```sql
DESCRIBE iceberg.default."cp_cluster__datagen-orders";
```
**Result:** ✅ **SUCCESS**  
**Output:**
```
ordertime    | bigint
orderid      | integer
itemid       | varchar
orderunits   | double
address      | row(city varchar, state varchar, zipcode bigint)
warpstream   | row(partition integer, offset bigint, key varbinary, value varbinary, timestamp timestamp(6))
```

#### Test 5: Data Query (Count)
```sql
SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders";
```
**Result:** ❌ **FAILED**

**Error:**
```
Query failed: io.trino.spi.TrinoException: Error processing metadata for table default.cp_cluster__datagen-orders

Caused by: java.lang.IllegalArgumentException: No FileSystem for scheme "azblob"
	at org.apache.hadoop.fs.FileSystem.getFileSystemClass(FileSystem.java:3443)
	at org.apache.hadoop.fs.FileSystem.createFileSystem(FileSystem.java:3466)
	at org.apache.hadoop.fs.Path.getFileSystem(Path.365)
	at org.apache.iceberg.hadoop.Util.getFs(Util.java:56)
```

#### Test 6: Data Query (Select)
```sql
SELECT * FROM iceberg.default."cp_cluster__datagen-orders" LIMIT 1;
```
**Result:** ❌ **FAILED** (same error)

#### Test 7: Iceberg Metadata Tables
```sql
SELECT * FROM iceberg.default."cp_cluster__datagen-orders$files" LIMIT 1;
```
**Result:** ❌ **FAILED**

**Error:**
```
Query failed: No factory for location: azblob://tableflow/warpstream/_tableflow/cp_cluster__datagen-orders-eb9c7e61-485b-4f93-8133-004b74003603/metadata/snap-01775062337545733804.avro
```

### Test Results Summary

| Operation | Status | Details |
|-----------|--------|---------|
| REST Catalog Connection | ✅ Works | Via HTTP proxy with auth header injection |
| SHOW CATALOGS | ✅ Works | Lists all available catalogs |
| SHOW SCHEMAS | ✅ Works | Returns `default`, `information_schema` |
| SHOW TABLES | ✅ Works | Returns `cp_cluster__datagen-orders` |
| DESCRIBE table | ✅ Works | Shows complete schema with all columns |
| SELECT queries | ❌ **FAILS** | Cannot read data files - `No FileSystem for scheme "azblob"` |
| Iceberg metadata queries | ❌ **FAILS** | Cannot access manifest/snapshot files |

### Issues Found

#### Issue 1: WarpStream Authentication
**Problem:** Trino Iceberg REST catalog lacks simple static Bearer token config  
**Solution:** ✅ Created HTTP proxy to inject `Authorization` header  
**Status:** RESOLVED

#### Issue 2: JSON Error Parsing
**Problem:** WarpStream returns plain "404" instead of JSON, causing Iceberg client errors  
**Solution:** ✅ Configured proxy to return proper JSON error responses  
**Status:** RESOLVED

#### Issue 3: azblob:// URI Format (BLOCKING)
**Problem:** Iceberg metadata contains `azblob://tableflow/...` file paths  
**Attempted Fix:** Mapped `fs.azblob.impl` to `AzureBlobFileSystem` in Hadoop config  
**Result:** ❌ FAILED - Hadoop cannot parse `azblob://` URLs (missing storage account name)  
**Status:** UNRESOLVED - Fundamental incompatibility

### Root Cause Analysis

**The URI Format Mismatch:**

| Component | URI Format | Example |
|-----------|------------|---------|
| WarpStream (Go SDK) | `azblob://container/path` | `azblob://tableflow/warpstream/_tableflow/...` |
| Hadoop ABFS | `abfss://container@account.endpoint/path` | `abfss://tableflow@wsdemostore.dfs.core.windows.net/warpstream/_tableflow/...` |

**Why Hadoop cannot support `azblob://`:**

1. **Missing Storage Account:** `azblob://` doesn't include the storage account name
2. **Missing Endpoint:** No `.dfs.core.windows.net` or `.blob.core.windows.net`
3. **Different Structure:** Cannot be parsed by Hadoop's ABFS FileSystem implementation
4. **SDK Mismatch:** `azblob://` is valid for Azure Go SDK, invalid for Java/Hadoop

**Where it fails:**
```
Trino Query → Iceberg Connector → Hadoop FileSystem API → 
  → Parse azblob://tableflow/... → 
    → FileSystem.getFileSystemClass("azblob") → 
      → No registered implementation → 
        → Exception: No FileSystem for scheme "azblob"
```

### Automated Test Script

A comprehensive test script is provided to run all tests automatically.

**Location:** `environment/trino/test.sh`

**What it does:**
1. Verifies Trino deployment is ready
2. Runs 7 tests covering metadata and data operations
3. Shows expected vs. actual results with color-coded output
4. Captures error messages for failed tests
5. Provides summary and root cause analysis

**Tests performed:**

| Test # | Operation | Expected Result | Verifies |
|--------|-----------|----------------|----------|
| 1 | `SHOW CATALOGS` | ✅ Pass | REST catalog connection works |
| 2 | `SHOW SCHEMAS FROM iceberg` | ✅ Pass | Schema discovery works |
| 3 | `SHOW TABLES FROM iceberg.default` | ✅ Pass | Table discovery works |
| 4 | `DESCRIBE table` | ✅ Pass | Metadata reading works |
| 5 | `SELECT COUNT(*)` | ❌ Fail | Data query fails with azblob:// error |
| 6 | `SELECT * LIMIT 1` | ❌ Fail | Data query fails with azblob:// error |
| 7 | `SELECT FROM $files` | ❌ Fail | Metadata files fail with azblob:// error |

**How to run:**

```bash
# Deploy Trino first (if not already deployed)
cd environment/trino
./deploy.sh

# Run all tests
./test.sh
```

**Expected output:**

```
========================================
Testing Trino with WarpStream Tableflow
========================================

✓ Trino is deployed and ready

========================================
Running Test Suite
========================================

----------------------------------------
Test: 1. Show Catalogs
Query: SHOW CATALOGS
Expected: ✅ SUCCESS

iceberg
jmx
memory
system
tpcds
tpch
✅ PASSED - Query succeeded as expected

----------------------------------------
Test: 5. Count Rows (Data Query)
Query: SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"
Expected: ❌ FAILURE

✅ PASSED - Query failed as expected

Error message:
Query failed: io.trino.spi.TrinoException: Error processing metadata
No FileSystem for scheme "azblob"
```

**Manual test commands:**

```bash
# Show catalogs
kubectl exec -n trino deployment/trino -- trino --execute "SHOW CATALOGS"

# Show tables (works)
kubectl exec -n trino deployment/trino -- trino --execute "SHOW TABLES FROM iceberg.default"

# Query data (fails)
kubectl exec -n trino deployment/trino -- trino --execute "SELECT COUNT(*) FROM iceberg.default.\"cp_cluster__datagen-orders\""

# View logs
kubectl logs -n trino deployment/trino --tail=100
kubectl logs -n trino deployment/warpstream-iceberg-proxy --tail=50
```

---

## 2. Apache Spark Testing

### Version & Components

- **Spark:** 3.5.1 (Scala 2.12, Java 17)
- **Iceberg Runtime:** 1.5.2
- **Hadoop Azure:** 3.3.4
- **Azure SDK:** 12.20.0+ (multiple jars)
- **Test Date:** 2026-04-01

### Infrastructure Deployed

#### 1. Spark Deployment with Init Container

**Init Container:** Downloads required JARs to `/spark-jars/`

**JARs Downloaded:**
```
iceberg-spark-runtime-3.5_2.12-1.5.2.jar
hadoop-azure-3.3.4.jar
azure-storage-blob-12.25.0.jar
azure-storage-common-12.25.0.jar
azure-storage-file-datalake-12.20.0.jar
azure-core-1.49.1.jar
azure-core-http-netty-1.15.0.jar
reactive-streams-1.0.4.jar
reactor-netty-http-1.1.17.jar
reactor-netty-core-1.1.17.jar
reactor-core-3.6.4.jar
netty-* (5 jars)
```

#### 2. Spark Configuration

**Spark Defaults (`spark-defaults.conf`):**
```properties
spark.sql.extensions=org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions
spark.sql.catalog.warpstream_iceberg=org.apache.iceberg.spark.SparkCatalog
spark.sql.catalog.warpstream_iceberg.type=rest
spark.sql.catalog.warpstream_iceberg.uri=https://metadata.default.eastus.azure.warpstream.com/catalogs/iceberg/vci_dl_d857ed96_bbbc_4289_8e06_75c77dcbfe12
spark.sql.catalog.warpstream_iceberg.header.Authorization=Bearer ${WARPSTREAM_AGENT_KEY}
spark.sql.catalog.warpstream_iceberg.warehouse=abfss://tableflow@wsdemostore.dfs.core.windows.net/warpstream/_tableflow
spark.sql.catalog.warpstream_iceberg.io-impl=org.apache.iceberg.azure.adlsv2.ADLSFileIO
spark.hadoop.fs.azure.account.key.wsdemostore.dfs.core.windows.net=${AZURE_STORAGE_KEY}
```

**Note:** Authorization header passed directly (no proxy needed)

### Tests Performed

#### Test 1: Catalog Namespaces
```bash
kubectl exec -n spark deployment/spark-sql -c spark-sql -- /opt/spark/bin/spark-sql \
  --jars /opt/spark/jars-extra/iceberg-spark-runtime-3.5_2.12-1.5.2.jar,... \
  -e "SHOW NAMESPACES FROM warpstream_iceberg;"
```
**Result:** ✅ **SUCCESS**  
**Output:** `default`

#### Test 2: Table Discovery
```sql
SHOW TABLES FROM warpstream_iceberg.default;
```
**Result:** ✅ **SUCCESS**  
**Output:** `cp_cluster__datagen-orders`

#### Test 3: Table Schema
```sql
DESCRIBE warpstream_iceberg.default.`cp_cluster__datagen-orders`;
```
**Result:** ✅ **SUCCESS**  
**Output:** Shows all columns with types

#### Test 4: Data Query (Count)
```sql
SELECT COUNT(*) FROM warpstream_iceberg.default.`cp_cluster__datagen-orders`;
```
**Result:** ❌ **FAILED**

**Error:**
```
org.apache.spark.SparkException: Job aborted due to stage failure
...
Caused by: org.apache.hadoop.fs.UnsupportedFileSystemException: No FileSystem for scheme "azblob"
	at org.apache.hadoop.fs.FileSystem.getFileSystemClass(FileSystem.java:3443)
	at org.apache.hadoop.fs.FileSystem.createFileSystem(FileSystem.java:3466)
	at org.apache.hadoop.fs.FileSystem$Cache.getInternal(FileSystem.java:3574)
	at org.apache.hadoop.fs.Path.getFileSystem(Path.java:365)
	at org.apache.iceberg.hadoop.Util.getFs(Util.java:56)
```

### Test Results Summary

| Operation | Status | Details |
|-----------|--------|---------|
| REST Catalog Connection | ✅ Works | Direct auth header (no proxy needed) |
| SHOW NAMESPACES | ✅ Works | Returns `default` |
| SHOW TABLES | ✅ Works | Returns `cp_cluster__datagen-orders` |
| DESCRIBE table | ✅ Works | Shows complete schema |
| SELECT queries | ❌ **FAILS** | `UnsupportedFileSystemException: No FileSystem for scheme "azblob"` |

### Root Cause Analysis

**Identical to Trino:**

Even though Spark is configured with:
- ✅ `ADLSFileIO` (Iceberg's Azure-specific file IO)
- ✅ `abfss://` warehouse path
- ✅ Azure storage account keys

**Spark still fails** because:

1. The `warehouse` path is only used for **writing new tables**
2. When **reading existing tables**, Spark uses file paths from Iceberg metadata
3. Those metadata files contain `azblob://` paths written by WarpStream
4. Hadoop FileSystem API (used by Spark) throws `UnsupportedFileSystemException`

**Proof that it's the same issue:**
- Exact same error class: `UnsupportedFileSystemException`
- Exact same error message: `No FileSystem for scheme "azblob"`
- Exact same stack trace location: `org.apache.hadoop.fs.FileSystem.getFileSystemClass`

### Automated Test Script

A comprehensive test script is provided to run all tests automatically.

**Location:** `environment/spark/test.sh`

**What it does:**
1. Verifies Spark deployment is ready
2. Checks that Iceberg JARs were downloaded by init container
3. Runs 5 tests covering metadata and data operations
4. Loads all 19 required JARs automatically
5. Shows expected vs. actual results with color-coded output
6. Captures error messages for failed tests
7. Provides summary and configuration details

**Tests performed:**

| Test # | Operation | Expected Result | Verifies |
|--------|-----------|----------------|----------|
| 1 | `SHOW NAMESPACES FROM warpstream_iceberg` | ✅ Pass | REST catalog connection works |
| 2 | `SHOW TABLES FROM warpstream_iceberg.default` | ✅ Pass | Table discovery works |
| 3 | `DESCRIBE table` | ✅ Pass | Metadata reading works |
| 4 | `SELECT COUNT(*)` | ❌ Fail | Data query fails with azblob:// error |
| 5 | `SELECT * LIMIT 1` | ❌ Fail | Data query fails with azblob:// error |

**JARs loaded automatically:**
```
iceberg-spark-runtime-3.5_2.12-1.5.2.jar     # Iceberg support
hadoop-azure-3.3.4.jar                        # Hadoop Azure connector
azure-storage-file-datalake-12.20.0.jar       # ADLS Gen2
azure-storage-blob-12.25.0.jar                # Blob storage
azure-storage-common-12.25.0.jar              # Common Azure types
azure-core-1.49.1.jar                         # Azure SDK core
+ 13 more dependency JARs (netty, reactor, etc.)
```

**How to run:**

```bash
# Deploy Spark first (if not already deployed)
cd environment/spark
./deploy.sh

# Run all tests
./test.sh
```

**Expected output:**

```
========================================
Testing Spark with WarpStream Tableflow
========================================

✓ Spark is deployed and ready
✓ Iceberg JARs are present

========================================
Running Test Suite
========================================

----------------------------------------
Test: 1. Show Namespaces from Catalog
Query: SHOW NAMESPACES FROM warpstream_iceberg;
Expected: ✅ SUCCESS

default
Time taken: 2.297 seconds, Fetched 1 row(s)
✅ PASSED - Query succeeded as expected

----------------------------------------
Test: 4. Count Rows (Data Query)
Query: SELECT COUNT(*) FROM warpstream_iceberg.default.`cp_cluster__datagen-orders`;
Expected: ❌ FAILURE

✅ PASSED - Query failed as expected

Error message:
org.apache.spark.SparkException: Job aborted due to stage failure
Caused by: org.apache.hadoop.fs.UnsupportedFileSystemException: No FileSystem for scheme "azblob"
```

**Manual test commands:**

```bash
# Show tables (works)
kubectl exec -n spark deployment/spark-sql -c spark-sql -- \
  /opt/spark/bin/spark-sql \
  --jars /opt/spark/jars-extra/iceberg-spark-runtime-3.5_2.12-1.5.2.jar,/opt/spark/jars-extra/hadoop-azure-3.3.4.jar,/opt/spark/jars-extra/azure-storage-file-datalake-12.20.0.jar,/opt/spark/jars-extra/azure-storage-blob-12.25.0.jar,/opt/spark/jars-extra/azure-storage-common-12.25.0.jar,/opt/spark/jars-extra/azure-core-1.49.1.jar \
  -e "SHOW TABLES FROM warpstream_iceberg.default;"

# Query data (fails)
kubectl exec -n spark deployment/spark-sql -c spark-sql -- \
  /opt/spark/bin/spark-sql \
  --jars /opt/spark/jars-extra/iceberg-spark-runtime-3.5_2.12-1.5.2.jar,/opt/spark/jars-extra/hadoop-azure-3.3.4.jar,/opt/spark/jars-extra/azure-storage-file-datalake-12.20.0.jar,/opt/spark/jars-extra/azure-storage-blob-12.25.0.jar,/opt/spark/jars-extra/azure-storage-common-12.25.0.jar,/opt/spark/jars-extra/azure-core-1.49.1.jar \
  -e "SELECT COUNT(*) FROM warpstream_iceberg.default.\\\`cp_cluster__datagen-orders\\\`;"

# View logs
kubectl logs -n spark deployment/spark-sql -c spark-sql --tail=100
kubectl logs -n spark deployment/spark-sql -c download-jars --tail=50
```

**Troubleshooting:**

If tests fail unexpectedly, check:

```bash
# Verify init container downloaded JARs
kubectl logs -n spark deployment/spark-sql -c download-jars

# Check JAR count (should be 19)
kubectl exec -n spark deployment/spark-sql -c spark-sql -- ls /opt/spark/jars-extra/ | wc -l

# Verify specific Iceberg JAR exists
kubectl exec -n spark deployment/spark-sql -c spark-sql -- ls -lh /opt/spark/jars-extra/iceberg-spark-runtime-3.5_2.12-1.5.2.jar
```

---

## Comparative Analysis

### Common Success Pattern

Both Trino and Spark successfully:

1. ✅ **Connect to WarpStream REST Catalog**
   - Trino: Via HTTP proxy
   - Spark: Direct header injection

2. ✅ **Discover Metadata**
   - List namespaces/schemas
   - List tables
   - Read table schema
   - Access column definitions

3. ✅ **Parse Iceberg Metadata**
   - Load table metadata JSON
   - Read schema definitions
   - Access table properties

### Common Failure Point

Both fail at the **exact same step**:

```
Step 1: Parse query ✅
Step 2: Load table metadata from REST catalog ✅
Step 3: Read Iceberg manifest files ✅
Step 4: Extract data file paths from manifest → azblob://... ❌
Step 5: Open data file with Hadoop FileSystem ❌ FAILS
```

**Error location (identical):**
```java
org.apache.hadoop.fs.FileSystem.getFileSystemClass()
  → looks up FileSystem for scheme "azblob"
  → No registered implementation found
  → throws UnsupportedFileSystemException
```

### Why Both Use Hadoop FileSystem

| Engine | Component | Uses Hadoop FS? | Why? |
|--------|-----------|----------------|------|
| Trino | Iceberg Connector | ✅ Yes | Built on Hadoop FileSystem API |
| Spark | Iceberg SparkCatalog | ✅ Yes | Even with ADLSFileIO, falls back to Hadoop FS for file reads |

**Key insight:** Both engines use Hadoop FileSystem as the underlying layer for file I/O, regardless of higher-level abstractions (like Iceberg's FileIO).

---

## Root Cause: URI Format Incompatibility

### The Core Problem

```
┌─────────────────────────────────────────────────────────────┐
│ WarpStream Tableflow (Azure Go SDK)                         │
│                                                              │
│ Writes to Iceberg metadata:                                 │
│   "file_path": "azblob://tableflow/warpstream/..."         │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Iceberg Manifest Files                                      │
│   - snap-*.avro                                             │
│   - manifest-*.avro                                         │
│   - Contains: azblob:// file paths                          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ Query Engines (Trino/Spark) via Hadoop FileSystem          │
│                                                              │
│ Hadoop FileSystem supported schemes:                        │
│   ✅ s3://   (AWS S3)                                       │
│   ✅ gs://   (Google Cloud Storage)                         │
│   ✅ abfs:// (Azure Data Lake Storage Gen2)                │
│   ✅ wasb:// (Azure Blob Storage - legacy)                 │
│   ✅ hdfs:// (Hadoop Distributed File System)              │
│   ✅ file:// (Local filesystem)                            │
│   ❌ azblob:// (NOT SUPPORTED)                             │
│                                                              │
│ Result: UnsupportedFileSystemException                      │
└─────────────────────────────────────────────────────────────┘
```

### URI Comparison

| What WarpStream Writes | What Hadoop Expects | Compatible? |
|------------------------|---------------------|-------------|
| `azblob://tableflow/warpstream/_tableflow/table-uuid/data/file.parquet` | `abfss://tableflow@wsdemostore.dfs.core.windows.net/warpstream/_tableflow/table-uuid/data/file.parquet` | ❌ **NO** |

**Why they're incompatible:**

1. **Scheme:** `azblob://` vs `abfss://`
2. **Storage Account:** Missing in `azblob://`, required in `abfss://`
3. **Endpoint:** Missing in `azblob://`, required in `abfss://` (`.dfs.core.windows.net`)
4. **SDK:** Azure Go SDK format vs Java/Hadoop format

### Why Mapping Doesn't Work

**Attempted workaround:**
```xml
<property>
  <name>fs.azblob.impl</name>
  <value>org.apache.hadoop.fs.azurebfs.AzureBlobFileSystem</value>
</property>
```

**Why it fails:**

Even if Hadoop recognizes `azblob://` as a scheme, the `AzureBlobFileSystem` implementation expects URLs in the format:
```
abfss://container@storageaccount.dfs.core.windows.net/path
```

It **cannot parse**:
```
azblob://container/path
```

Because it doesn't know:
- Which storage account to use?
- Which endpoint (`.blob.core.windows.net` or `.dfs.core.windows.net`)?

---

## Impact Assessment

### What This Means for Hadoop-Based Engines

All query engines that use Hadoop FileSystem API will fail:

| Engine | Uses Hadoop FS? | Will Fail? | Tested? |
|--------|----------------|------------|---------|
| **Trino** | ✅ Yes | ✅ CONFIRMED | ✅ Yes |
| **Spark** | ✅ Yes | ✅ CONFIRMED | ✅ Yes |
| **Presto** | ✅ Yes | ✅ Likely | ❌ No |
| **Hive** | ✅ Yes | ✅ Definitely | ❌ No |
| **Impala** | ✅ Yes | ✅ Definitely | ❌ No |
| **Flink** | ⚠️ Partial | ⚠️ Maybe | ❌ No |

**Why Flink might be different:**
- Flink has better Azure SDK integration
- May use native Azure clients instead of Hadoop FS
- Worth testing but no guarantee

---

## Solutions & Recommendations

### Solution 1: WarpStream Enhancement ⭐ **RECOMMENDED**

**Request WarpStream to support `abfss://` URIs for Azure deployments**

**Feature Request:**
- Auto-detect Azure Blob Storage backend
- Write `abfss://container@account.dfs.core.windows.net/path` instead of `azblob://container/path`
- Make it configurable via Tableflow settings
- Maintain backward compatibility

**Impact if implemented:**
- ✅ Fixes ALL query engines at once (Trino, Spark, Presto, Hive, etc.)
- ✅ Preserves full Iceberg functionality
- ✅ Aligns with Azure best practices
- ✅ No infrastructure changes needed

### Solution 2: Custom FileSystem Implementation

**Build Hadoop FileSystem for `azblob://` scheme**

**Approach:**
```java
public class AzBlobFileSystem extends FileSystem {
  // Translate azblob:// to Azure SDK calls
  // Map azblob://container/path → container + path
  // Use hardcoded or configured storage account
}
```

**Challenges:**
- 🔴 High complexity (custom Hadoop plugin)
- 🔴 Must be deployed to every engine
- 🔴 How to determine storage account from URL?
- 🔴 Maintenance burden
- 🔴 Non-standard, fragile solution

**Not recommended** - Wait for WarpStream fix instead

### Solution 3: Direct Parquet Access (Temporary Workaround)

**Bypass Iceberg metadata entirely**

```sql
-- Spark
SELECT * FROM parquet.`abfss://tableflow@wsdemostore.dfs.core.windows.net/warpstream/_tableflow/*/data/*.parquet`;

-- DuckDB
SELECT * FROM read_parquet('abfss://tableflow@wsdemostore.dfs.core.windows.net/warpstream/_tableflow/*/data/*.parquet');
```

**Pros:**
- ✅ Works immediately
- ✅ Can query data now

**Cons:**
- ❌ No schema evolution
- ❌ No time travel
- ❌ No snapshot metadata
- ❌ Manual schema management
- ❌ Loses all Iceberg benefits

**Use case:** Temporary solution while waiting for WarpStream fix

---

## Conclusion

### Summary of Findings

1. **Both Trino and Spark fail** at the exact same point with the exact same error
2. **HTTP proxy successfully handles authentication** but doesn't solve the URI issue
3. **Hadoop FileSystem limitation** affects all Java-based query engines
4. **Only solution** is for WarpStream to support `abfss://` URIs or test non-Hadoop engines (Dremio, Flink)

### Test Artifacts

All testing infrastructure is preserved in:
- `environment/trino/` - Trino deployment with HTTP proxy
- `environment/spark/` - Spark deployment with Iceberg JARs
- Both include deployment scripts and documentation

### Next Steps

**Priority 1:** Contact WarpStream support with this analysis and request `abfss://` URI support

**Priority 2:** Test Apache Flink SQL (may have better Azure SDK integration)

**Priority 3:** Consider Dremio if immediate solution needed (native Iceberg, not Hadoop-based)

---

## References

- [WarpStream Tableflow Documentation](https://docs.warpstream.com/warpstream/tableflow/tableflow)
- [Apache Iceberg Azure Integration](https://iceberg.apache.org/docs/latest/azure/)
- [Hadoop Azure Support](https://hadoop.apache.org/docs/stable/hadoop-azure/index.html)
- [Trino Iceberg Connector](https://trino.io/docs/current/connector/iceberg.html)
- [Spark Iceberg Integration](https://iceberg.apache.org/docs/latest/spark-configuration/)
