#!/bin/bash
set -euo pipefail

echo "======================================"
echo "Deploying Trino with Iceberg Support"
echo "======================================"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"

# Get VCI from WarpStream agent
VCI=$(kubectl exec -n warpstream deployment/warpstream-agent -- printenv WARPSTREAM_DEFAULT_VIRTUAL_CLUSTER_ID)
echo "Using Virtual Cluster ID: $VCI"

# Ensure secrets exist
if ! kubectl get secret azure-storage-secret -n confluent &>/dev/null; then
    echo "ERROR: azure-storage-secret not found in confluent namespace!"
    exit 1
fi

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

# Copy secrets to trino namespace if they don't exist there
if ! kubectl get secret azure-storage-secret -n trino &>/dev/null; then
    echo "Copying azure-storage-secret to trino namespace..."
    kubectl get secret azure-storage-secret -n confluent -o yaml | \
        sed 's/namespace: confluent/namespace: trino/' | \
        kubectl apply -f -
fi

if ! kubectl get secret warpstream-agent-apikey -n trino &>/dev/null; then
    echo "Copying warpstream-agent-apikey to trino namespace..."
    kubectl get secret warpstream-agent-apikey -n warpstream -o yaml | \
        sed 's/namespace: warpstream/namespace: trino/' | \
        kubectl apply -f -
fi

# Update ConfigMap with current VCI
echo "Updating Trino configuration with VCI: $VCI..."
sed "s|vci_dl_d857ed96_bbbc_4289_8e06_75c77dcbfe12|${VCI}|g" "$K8S_DIR/configmap.yaml" | kubectl apply -f -

# Deploy HTTP proxy for WarpStream authorization
echo "Deploying WarpStream proxy..."
kubectl apply -f "$K8S_DIR/proxy-configmap.yaml"
kubectl apply -f "$K8S_DIR/proxy-service.yaml"
kubectl apply -f "$K8S_DIR/proxy-deployment.yaml"

# Apply Service
echo "Creating Trino service..."
kubectl apply -f "$K8S_DIR/service.yaml"

# Apply Deployment
echo "Deploying Trino..."
kubectl apply -f "$K8S_DIR/deployment.yaml"

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
echo "⚠️  IMPORTANT: Trino cannot query data due to azblob:// URI limitation"
echo ""
echo "What works:"
echo "  ✅ SHOW CATALOGS"
echo "  ✅ SHOW SCHEMAS FROM iceberg"
echo "  ✅ SHOW TABLES FROM iceberg.default"
echo "  ✅ DESCRIBE table"
echo ""
echo "What fails:"
echo "  ❌ SELECT queries - No FileSystem for scheme 'azblob'"
echo ""
echo "Test commands:"
echo "  kubectl exec -n trino deployment/trino -- trino --execute 'SHOW CATALOGS'"
echo "  kubectl exec -n trino deployment/trino -- trino --execute 'SHOW TABLES FROM iceberg.default'"
echo ""
echo "Port forward to access UI:"
echo "  kubectl port-forward -n trino svc/trino 8080:8080"
echo "  Then open: http://localhost:8080"
echo ""
