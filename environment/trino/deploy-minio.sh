#!/bin/bash

################################################################################
# Script: deploy-minio.sh
# Description: Deploy Trino with MinIO backend support
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"

# Source common functions
source "${PROJECT_ROOT}/scripts/common/colors.sh"

echo "======================================"
echo "Deploying Trino with MinIO Backend"
echo "======================================"

# Check required variables
if [ -z "${WARPSTREAM_VIRTUAL_CLUSTER_ID:-}" ]; then
  echo -e "${RED}Error: WARPSTREAM_VIRTUAL_CLUSTER_ID is not set${NC}"
  exit 1
fi

VCI="${WARPSTREAM_VIRTUAL_CLUSTER_ID}"
echo "Using Virtual Cluster ID: $VCI"

# Ensure required secrets exist
if ! kubectl get secret warpstream-agent-apikey -n warpstream &>/dev/null; then
    echo "ERROR: warpstream-agent-apikey not found in warpstream namespace!"
    exit 1
fi

echo "✓ Required secrets found"

# Apply namespace
echo "Creating Trino namespace..."
kubectl apply -f "$K8S_DIR/namespace.yaml"

# Wait a moment for namespace to be ready
sleep 2

# Copy WarpStream secret to trino namespace if it doesn't exist there
if ! kubectl get secret warpstream-agent-apikey -n trino &>/dev/null; then
    echo "Copying warpstream-agent-apikey to trino namespace..."
    kubectl get secret warpstream-agent-apikey -n warpstream -o yaml | \
        sed 's/namespace: warpstream/namespace: trino/' | \
        kubectl apply -f -
fi

# Get WarpStream cloud config from Terraform state (this is the source of truth)
WARPSTREAM_TF_DIR="${PROJECT_ROOT}/environment/warpstream/cluster"
echo -e "${CYAN}Reading WarpStream cluster configuration from Terraform...${NC}"

if [ ! -d "$WARPSTREAM_TF_DIR" ]; then
  echo -e "${RED}Error: WarpStream Terraform directory not found: $WARPSTREAM_TF_DIR${NC}"
  exit 1
fi

WARPSTREAM_CLOUD_CONFIG=$(cd "$WARPSTREAM_TF_DIR" && terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type == "warpstream_tableflow_cluster") | .values.cloud' 2>/dev/null || echo "")

if [ -z "$WARPSTREAM_CLOUD_CONFIG" ]; then
  echo -e "${RED}Error: Could not read WarpStream cluster cloud configuration from Terraform${NC}"
  exit 1
fi

WARPSTREAM_CLOUD_PROVIDER=$(echo "$WARPSTREAM_CLOUD_CONFIG" | jq -r '.provider')
WARPSTREAM_CLOUD_REGION=$(echo "$WARPSTREAM_CLOUD_CONFIG" | jq -r '.region')

echo -e "${GREEN}✓ WarpStream cluster cloud: ${WARPSTREAM_CLOUD_PROVIDER} / ${WARPSTREAM_CLOUD_REGION}${NC}"

# Update ConfigMap with current VCI and region
echo "Updating Trino configuration with VCI: $VCI and region: $WARPSTREAM_CLOUD_REGION..."
sed -e "s|<WARPSTREAM_VIRTUAL_CLUSTER_ID>|${VCI}|g" \
    -e "s|<WARPSTREAM_CONTROL_PLANE_REGION>|${WARPSTREAM_CLOUD_REGION}|g" \
    "$K8S_DIR/configmap-minio.yaml" | kubectl apply -f -

# Determine WarpStream metadata URL based on cloud provider
if [ "$WARPSTREAM_CLOUD_PROVIDER" = "aws" ]; then
  METADATA_URL="metadata.default.${WARPSTREAM_CLOUD_REGION}.warpstream.com"
elif [ "$WARPSTREAM_CLOUD_PROVIDER" = "gcp" ]; then
  METADATA_URL="metadata.default.${WARPSTREAM_CLOUD_REGION}.gcp.warpstream.com"
else
  # Azure
  METADATA_URL="metadata.default.${WARPSTREAM_CLOUD_REGION}.azure.warpstream.com"
fi

echo -e "${GREEN}✓ Using WarpStream metadata URL: ${METADATA_URL}${NC}"

# Deploy HTTP proxy for WarpStream authorization with correct metadata URL
echo "Deploying WarpStream proxy..."
temp_proxy_config=$(mktemp)
sed "s|<METADATA_URL>|${METADATA_URL}|g" \
  "$K8S_DIR/proxy-configmap.yaml" > "$temp_proxy_config"
kubectl apply -f "$temp_proxy_config"
rm -f "$temp_proxy_config"

kubectl apply -f "$K8S_DIR/proxy-service.yaml"
kubectl apply -f "$K8S_DIR/proxy-deployment.yaml"

# Apply Service
echo "Creating Trino service..."
kubectl apply -f "$K8S_DIR/service.yaml"

# Apply Deployment with region replacement
echo "Deploying Trino..."
temp_deployment=$(mktemp)
sed "s|<WARPSTREAM_CONTROL_PLANE_REGION>|${WARPSTREAM_CLOUD_REGION}|g" \
  "$K8S_DIR/deployment-minio.yaml" > "$temp_deployment"
kubectl apply -f "$temp_deployment"
rm -f "$temp_deployment"

# Wait for deployments
echo ""
echo "Waiting for deployments to be ready..."
kubectl wait --for=condition=available --timeout=120s deployment/warpstream-iceberg-proxy -n trino
kubectl wait --for=condition=available --timeout=300s deployment/trino -n trino

echo ""
echo "======================================"
echo "Trino Deployment Complete!"
echo "======================================"
echo ""
echo "✅ Trino is ready to query WarpStream Tableflow data from MinIO!"
echo ""
echo "Test commands:"
echo "  kubectl exec -n trino deployment/trino -- trino --execute 'SHOW CATALOGS'"
echo "  kubectl exec -n trino deployment/trino -- trino --execute 'SHOW SCHEMAS FROM iceberg'"
echo "  kubectl exec -n trino deployment/trino -- trino --execute 'SHOW TABLES FROM iceberg.default'"
echo "  kubectl exec -n trino deployment/trino -- trino --execute 'SELECT COUNT(*) FROM iceberg.default.\"cp_cluster__datagen-orders\"'"
echo ""
echo "Port forward to access UI:"
echo "  kubectl port-forward -n trino svc/trino 8080:8080"
echo "  Then open: http://localhost:8080"
echo ""
