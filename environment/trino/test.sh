#!/bin/bash
set -euo pipefail

echo "========================================"
echo "Testing Trino with WarpStream Tableflow"
echo "========================================"
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

    if kubectl exec -n trino deployment/trino -- timeout 30 trino --execute "$query" 2>&1 | tee /tmp/trino-test-output.txt; then
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
            grep -E "failed|Error|Exception" /tmp/trino-test-output.txt | head -3 || echo "(No error message captured)"
        else
            echo -e "${RED}❌ FAILED${NC} - Query failed unexpectedly"
            echo ""
            echo "Error message:"
            grep -E "failed|Error|Exception" /tmp/trino-test-output.txt | head -3 || echo "(No error message captured)"
        fi
    fi
    echo ""
}

# Check if Trino is deployed
echo "Checking Trino deployment..."
if ! kubectl get deployment trino -n trino &>/dev/null; then
    echo -e "${RED}ERROR: Trino is not deployed!${NC}"
    echo "Run ./deploy.sh first"
    exit 1
fi

# Check if Trino is ready
if ! kubectl wait --for=condition=available --timeout=10s deployment/trino -n trino &>/dev/null; then
    echo -e "${RED}ERROR: Trino is not ready!${NC}"
    echo "Check pod status: kubectl get pods -n trino"
    exit 1
fi

echo -e "${GREEN}✓ Trino is deployed and ready${NC}"
echo ""

# Run tests
echo "========================================"
echo "Running Test Suite"
echo "========================================"
echo ""

# Test 1: Show Catalogs (should succeed)
run_test \
    "1. Show Catalogs" \
    "SHOW CATALOGS" \
    "true"

# Test 2: Show Schemas (should succeed)
run_test \
    "2. Show Schemas from Iceberg Catalog" \
    "SHOW SCHEMAS FROM iceberg" \
    "true"

# Test 3: Show Tables (should succeed)
run_test \
    "3. Show Tables from Default Schema" \
    "SHOW TABLES FROM iceberg.default" \
    "true"

# Test 4: Describe Table (should succeed)
run_test \
    "4. Describe Table Schema" \
    "DESCRIBE iceberg.default.\\\"cp_cluster__datagen-orders\\\"" \
    "true"

# Test 5: Count Query (should fail with azblob error)
run_test \
    "5. Count Rows (Data Query)" \
    "SELECT COUNT(*) FROM iceberg.default.\\\"cp_cluster__datagen-orders\\\"" \
    "false"

# Test 6: Select Query (should fail with azblob error)
run_test \
    "6. Select Data (Data Query)" \
    "SELECT * FROM iceberg.default.\\\"cp_cluster__datagen-orders\\\" LIMIT 1" \
    "false"

# Test 7: Iceberg Metadata Table (should fail with azblob error)
run_test \
    "7. Query Iceberg Files Metadata" \
    "SELECT file_path FROM iceberg.default.\\\"cp_cluster__datagen-orders\\\$files\\\" LIMIT 1" \
    "false"

# Summary
echo "========================================"
echo "Test Summary"
echo "========================================"
echo ""
echo -e "${GREEN}Expected Results:${NC}"
echo "  ✅ Tests 1-4: Metadata operations (SHOULD PASS)"
echo "  ❌ Tests 5-7: Data queries (SHOULD FAIL - azblob:// error)"
echo ""
echo -e "${YELLOW}Key Finding:${NC}"
echo "  Trino can access catalog metadata but cannot read data files"
echo "  due to 'No FileSystem for scheme azblob' error"
echo ""
echo -e "${YELLOW}Root Cause:${NC}"
echo "  WarpStream writes azblob:// URIs in Iceberg metadata"
echo "  Hadoop FileSystem (used by Trino) does not support azblob://"
echo "  Hadoop supports: s3://, gs://, abfs://, wasb://, hdfs://, file://"
echo ""
echo "For detailed analysis, see: ../../OSS_QUERY_ENGINES.md"
echo ""
