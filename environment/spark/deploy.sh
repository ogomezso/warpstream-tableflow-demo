#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "========================================"
echo "Deploying Apache Spark with Iceberg"
echo "========================================"
echo ""

# Get credentials from secrets
echo "📦 Gathering credentials..."
AZURE_STORAGE_ACCOUNT=$(kubectl get secret -n confluent azure-storage-secret -o jsonpath='{.data.AZURE_STORAGE_ACCOUNT}' | base64 -d 2>/dev/null || echo "wsdemostore")
AZURE_STORAGE_KEY=$(kubectl get secret -n confluent azure-storage-secret -o jsonpath='{.data.AZURE_STORAGE_KEY}' | base64 -d)
WARPSTREAM_AGENT_KEY=$(kubectl get secret -n warpstream warpstream-agent-apikey -o jsonpath='{.data.apikey}' | base64 -d)

echo "   Storage Account: $AZURE_STORAGE_ACCOUNT"
echo "   Storage Key: ${AZURE_STORAGE_KEY:0:20}..."
echo "   Agent Key: ${WARPSTREAM_AGENT_KEY:0:20}..."

# Get VCI from WarpStream agent
VCI=$(kubectl exec -n warpstream deployment/warpstream-agent -- printenv WARPSTREAM_DEFAULT_VIRTUAL_CLUSTER_ID)

# WarpStream REST catalog URI
WARPSTREAM_ICEBERG_REST_URI="https://metadata.default.eastus.azure.warpstream.com/catalogs/iceberg/${VCI}"
ICEBERG_WAREHOUSE="abfs://tableflow@${AZURE_STORAGE_ACCOUNT}.dfs.core.windows.net/warpstream/_tableflow"

echo ""
echo "🔧 Configuration:"
echo "   REST Catalog: $WARPSTREAM_ICEBERG_REST_URI"
echo "   Warehouse: $ICEBERG_WAREHOUSE"
echo ""

# Function to escape special characters for sed
escape_for_sed() {
    echo "$1" | sed 's/[&/\]/\\&/g'
}

# Escape values for sed
ESCAPED_REST_URI=$(escape_for_sed "$WARPSTREAM_ICEBERG_REST_URI")
ESCAPED_AGENT_KEY=$(escape_for_sed "$WARPSTREAM_AGENT_KEY")
ESCAPED_STORAGE_KEY=$(escape_for_sed "$AZURE_STORAGE_KEY")
ESCAPED_WAREHOUSE=$(escape_for_sed "$ICEBERG_WAREHOUSE")

echo "📝 Applying Kubernetes manifests..."

# Apply namespace
kubectl apply -f "${SCRIPT_DIR}/k8s/namespace.yaml"

# Apply ConfigMap with substitutions
sed -e "s|WARPSTREAM_ICEBERG_REST_URI_PLACEHOLDER|${ESCAPED_REST_URI}|g" \
    -e "s|WARPSTREAM_AGENT_KEY_PLACEHOLDER|${ESCAPED_AGENT_KEY}|g" \
    -e "s|ICEBERG_WAREHOUSE_PLACEHOLDER|${ESCAPED_WAREHOUSE}|g" \
    -e "s|AZURE_STORAGE_ACCOUNT_PLACEHOLDER|${AZURE_STORAGE_ACCOUNT}|g" \
    -e "s|AZURE_STORAGE_KEY_PLACEHOLDER|${ESCAPED_STORAGE_KEY}|g" \
    "${SCRIPT_DIR}/k8s/configmap.yaml" | kubectl apply -f -

# Apply Deployment with substitutions
sed -e "s|AZURE_STORAGE_ACCOUNT_PLACEHOLDER|${AZURE_STORAGE_ACCOUNT}|g" \
    -e "s|AZURE_STORAGE_KEY_PLACEHOLDER|${ESCAPED_STORAGE_KEY}|g" \
    -e "s|WARPSTREAM_AGENT_KEY_PLACEHOLDER|${ESCAPED_AGENT_KEY}|g" \
    "${SCRIPT_DIR}/k8s/deployment.yaml" | kubectl apply -f -

# Apply Service
kubectl apply -f "${SCRIPT_DIR}/k8s/service.yaml"

echo ""
echo "⏳ Waiting for Spark to be ready..."
kubectl wait --for=condition=available --timeout=180s deployment/spark-sql -n spark

echo ""
echo "========================================"
echo "✅ Spark Deployed Successfully!"
echo "========================================"
echo ""
echo "Test with Spark SQL:"
echo "  kubectl exec -n spark deployment/spark-sql -- spark-sql \\"
echo "    -e \"SHOW TABLES IN warpstream_iceberg.default\""
echo ""
echo "Query data:"
echo "  kubectl exec -n spark deployment/spark-sql -- spark-sql \\"
echo "    -e \"SELECT COUNT(*) FROM warpstream_iceberg.default.cp_cluster__datagen_orders\""
echo ""
echo "Interactive shell:"
echo "  kubectl exec -it -n spark deployment/spark-sql -- spark-sql"
echo ""
echo "Sample queries once in the shell:"
echo "  SHOW TABLES IN warpstream_iceberg.default;"
echo "  SELECT * FROM warpstream_iceberg.default.cp_cluster__datagen_orders LIMIT 10;"
echo ""
