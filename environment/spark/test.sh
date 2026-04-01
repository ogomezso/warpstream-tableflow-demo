#!/bin/bash
set -euo pipefail

echo "========================================"
echo "Testing Spark with WarpStream Tableflow"
echo "========================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Build JARs classpath
JARS="/opt/spark/jars-extra/iceberg-spark-runtime-3.5_2.12-1.5.2.jar"
JARS="${JARS},/opt/spark/jars-extra/hadoop-azure-3.3.4.jar"
JARS="${JARS},/opt/spark/jars-extra/azure-storage-file-datalake-12.20.0.jar"
JARS="${JARS},/opt/spark/jars-extra/azure-storage-blob-12.25.0.jar"
JARS="${JARS},/opt/spark/jars-extra/azure-storage-common-12.25.0.jar"
JARS="${JARS},/opt/spark/jars-extra/azure-core-1.49.1.jar"

# Function to run a test
run_test() {
    local test_name="$1"
    local query="$2"
    local should_succeed="${3:-true}"

    echo "----------------------------------------"
    echo "Test: $test_name"
    echo "Query: $query"
    echo "Expected: $([ "$should_succeed" = "true" ] && echo "✅ SUCCESS" || echo "❌ FAILURE")"
    echo ""

    if kubectl exec -n spark deployment/spark-sql -c spark-sql -- timeout 60 /opt/spark/bin/spark-sql \
        --jars "$JARS" \
        -e "$query" 2>&1 | tee /tmp/spark-test-output.txt | tail -20; then
        if [ "$should_succeed" = "true" ]; then
            echo -e "${GREEN}✅ PASSED${NC} - Query succeeded as expected"
        else
            echo -e "${YELLOW}⚠️  UNEXPECTED${NC} - Query succeeded but was expected to fail"
        fi
    else
        if [ "$should_succeed" = "false" ]; then
            echo -e "${GREEN}✅ PASSED${NC} - Query failed as expected"
            echo ""
            echo "Error message:"
            grep -E "Exception|failed|Error" /tmp/spark-test-output.txt | grep -v "WARN" | head -3 || echo "(No error message captured)"
        else
            echo -e "${RED}❌ FAILED${NC} - Query failed unexpectedly"
            echo ""
            echo "Error message:"
            grep -E "Exception|failed|Error" /tmp/spark-test-output.txt | grep -v "WARN" | head -3 || echo "(No error message captured)"
        fi
    fi
    echo ""
}

# Check if Spark is deployed
echo "Checking Spark deployment..."
if ! kubectl get deployment spark-sql -n spark &>/dev/null; then
    echo -e "${RED}ERROR: Spark is not deployed!${NC}"
    echo "Run ./deploy.sh first"
    exit 1
fi

# Check if Spark is ready
if ! kubectl wait --for=condition=available --timeout=10s deployment/spark-sql -n spark &>/dev/null; then
    echo -e "${RED}ERROR: Spark is not ready!${NC}"
    echo "Check pod status: kubectl get pods -n spark"
    exit 1
fi

echo -e "${GREEN}✓ Spark is deployed and ready${NC}"
echo ""

# Check if JARs are present
echo "Checking if Iceberg JARs are available..."
if ! kubectl exec -n spark deployment/spark-sql -c spark-sql -- test -f /opt/spark/jars-extra/iceberg-spark-runtime-3.5_2.12-1.5.2.jar; then
    echo -e "${RED}ERROR: Iceberg JARs not found!${NC}"
    echo "The init container may have failed. Check logs:"
    echo "  kubectl logs -n spark deployment/spark-sql -c download-jars"
    exit 1
fi

echo -e "${GREEN}✓ Iceberg JARs are present${NC}"
echo ""

# Run tests
echo "========================================"
echo "Running Test Suite"
echo "========================================"
echo ""

# Test 1: Show Namespaces (should succeed)
run_test \
    "1. Show Namespaces from Catalog" \
    "SHOW NAMESPACES FROM warpstream_iceberg;" \
    "true"

# Test 2: Show Tables (should succeed)
run_test \
    "2. Show Tables from Default Namespace" \
    "SHOW TABLES FROM warpstream_iceberg.default;" \
    "true"

# Test 3: Describe Table (should succeed)
run_test \
    "3. Describe Table Schema" \
    "DESCRIBE warpstream_iceberg.default.\\\`cp_cluster__datagen-orders\\\`;" \
    "true"

# Test 4: Count Query (should fail with azblob error)
run_test \
    "4. Count Rows (Data Query)" \
    "SELECT COUNT(*) FROM warpstream_iceberg.default.\\\`cp_cluster__datagen-orders\\\`;" \
    "false"

# Test 5: Select Query (should fail with azblob error)
run_test \
    "5. Select Data (Data Query)" \
    "SELECT * FROM warpstream_iceberg.default.\\\`cp_cluster__datagen-orders\\\` LIMIT 1;" \
    "false"

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo ""
echo -e "${GREEN}Expected Results:${NC}"
echo "  ✅ Tests 1-3: Metadata operations (SHOULD PASS)"
echo "  ❌ Tests 4-5: Data queries (SHOULD FAIL - azblob:// error)"
echo ""
echo -e "${YELLOW}Key Finding:${NC}"
echo "  Spark can access catalog metadata but cannot read data files"
echo "  due to 'UnsupportedFileSystemException: No FileSystem for scheme azblob'"
echo ""
echo -e "${YELLOW}Root Cause:${NC}"
echo "  WarpStream writes azblob:// URIs in Iceberg metadata"
echo "  Hadoop FileSystem (used by Spark) does not support azblob://"
echo "  Even with ADLSFileIO configured, Spark falls back to Hadoop FS for file reads"
echo ""
echo -e "${YELLOW}Configuration Details:${NC}"
echo "  - Using Iceberg SparkCatalog with REST catalog type"
echo "  - Configured with ADLSFileIO for Azure"
echo "  - 19 JARs loaded including azure-storage-file-datalake"
echo "  - Still fails because metadata contains azblob:// paths"
echo ""
echo "For detailed analysis, see: ../../OSS_QUERY_ENGINES.md"
echo ""
