#!/bin/bash
################################################################################
# Script: deploy.sh
# Description: Deploy MinIO to Kubernetes for WarpStream Tableflow backend
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MINIO_NAMESPACE="${MINIO_NAMESPACE:-minio}"
MINIO_READY_TIMEOUT="${MINIO_READY_TIMEOUT:-300s}"

# Source common modules if available
if [ -f "${SCRIPT_DIR}/../../scripts/common/colors.sh" ]; then
  source "${SCRIPT_DIR}/../../scripts/common/colors.sh"
else
  # Define colors if not available
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  NC='\033[0m'
fi

echo -e "${YELLOW}Deploying MinIO to Kubernetes...${NC}"

# Create namespace
echo "Creating namespace: ${MINIO_NAMESPACE}"
kubectl apply -f "${SCRIPT_DIR}/namespace.yaml"

# Deploy MinIO
echo "Deploying MinIO..."
kubectl apply -f "${SCRIPT_DIR}/deployment.yaml"

# Wait for MinIO to be ready
echo "Waiting for MinIO to be ready (timeout: ${MINIO_READY_TIMEOUT})..."
kubectl wait --for=condition=available --timeout="${MINIO_READY_TIMEOUT}" \
  deployment/minio -n "${MINIO_NAMESPACE}"

# Initialize MinIO (create bucket)
echo "Initializing MinIO bucket..."
kubectl apply -f "${SCRIPT_DIR}/init-job.yaml"
kubectl wait --for=condition=complete --timeout=120s job/minio-init -n "${MINIO_NAMESPACE}" || true

echo -e "${GREEN}✓ MinIO deployment complete${NC}"
echo
echo "MinIO is available at:"
echo "  API: http://minio.${MINIO_NAMESPACE}.svc.cluster.local:9000"
echo "  Console: http://minio.${MINIO_NAMESPACE}.svc.cluster.local:9001"
echo "  Credentials: minioadmin / minioadmin"
echo
echo "To access the console locally, run:"
echo "  kubectl port-forward -n ${MINIO_NAMESPACE} svc/minio 9001:9001"
echo
