#!/bin/bash
set -euo pipefail

echo "======================================"
echo "Deploying Trino with MinIO Backend"
echo "======================================"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K8S_DIR="$SCRIPT_DIR/k8s"

# Get VCI from WarpStream agent
VCI=$(kubectl exec -n warpstream deployment/warpstream-agent -- printenv WARPSTREAM_DEFAULT_VIRTUAL_CLUSTER_ID)
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

# Update ConfigMap with current VCI
echo "Updating Trino configuration with VCI: $VCI..."
sed "s|<WARPSTREAM_VIRTUAL_CLUSTER_ID>|${VCI}|g" "$K8S_DIR/configmap-minio.yaml" | kubectl apply -f -

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
kubectl apply -f "$K8S_DIR/deployment-minio.yaml"

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
