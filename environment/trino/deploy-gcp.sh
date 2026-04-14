#!/bin/bash

################################################################################
# Script: deploy-gcp.sh
# Description: Deploy Trino with GCP GCS native filesystem support
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common functions
source "${PROJECT_ROOT}/scripts/common/colors.sh"

echo -e "${CYAN}Deploying Trino for GCP GCS backend...${NC}"

# Check required variables
if [ -z "${WARPSTREAM_VIRTUAL_CLUSTER_ID:-}" ]; then
  echo -e "${RED}Error: WARPSTREAM_VIRTUAL_CLUSTER_ID is not set${NC}"
  exit 1
fi

if [ -z "${GCP_PROJECT:-}" ]; then
  echo -e "${RED}Error: GCP_PROJECT is not set${NC}"
  exit 1
fi

# Safety check: prevent using production project
if [ "${GCP_PROJECT}" = "claude-code-prod" ]; then
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}Error: Cannot deploy Trino with production project${NC}"
  echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${RED}GCP_PROJECT is set to '${GCP_PROJECT}' (production project)${NC}"
  echo -e "${RED}This would allow Trino to access production GCS buckets!${NC}"
  echo
  echo "Please use a development or demo project instead."
  echo
  exit 1
fi

# Create namespace
kubectl apply -f "${SCRIPT_DIR}/k8s/namespace.yaml"

# Copy WarpStream agent API key secret from warpstream namespace to trino namespace
# (needed for the proxy to authenticate with WarpStream)
echo -e "${CYAN}Copying WarpStream agent API key secret to trino namespace...${NC}"
if kubectl get secret warpstream-agent-apikey -n warpstream &>/dev/null; then
  kubectl get secret warpstream-agent-apikey -n warpstream -o yaml | \
    sed 's/namespace: warpstream/namespace: trino/' | \
    kubectl apply -f -
else
  echo -e "${YELLOW}Warning: warpstream-agent-apikey secret not found in warpstream namespace${NC}"
  echo -e "${YELLOW}The proxy may fail to start. Make sure WarpStream agent is deployed first.${NC}"
fi

# Determine WarpStream metadata URL based on GCP region
METADATA_URL="metadata.default.${GCP_REGION}.gcp.warpstream.com"
echo -e "${CYAN}Using WarpStream metadata URL: ${METADATA_URL}${NC}"

# Deploy WarpStream proxy (for REST catalog auth) with correct metadata URL
temp_proxy_config=$(mktemp)
sed "s|<METADATA_URL>|${METADATA_URL}|g" \
  "${SCRIPT_DIR}/k8s/proxy-configmap.yaml" > "$temp_proxy_config"
kubectl apply -f "$temp_proxy_config"
rm -f "$temp_proxy_config"

kubectl apply -f "${SCRIPT_DIR}/k8s/proxy-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/proxy-service.yaml"

# Create GCP credentials secret in trino namespace
echo -e "${CYAN}Creating GCP credentials secret in trino namespace...${NC}"

# Get service account key (should be created during GCP authentication)
if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]; then
  kubectl create secret generic gcp-storage-credentials \
    --from-file=credentials.json="${GOOGLE_APPLICATION_CREDENTIALS}" \
    --namespace=trino \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo -e "${YELLOW}Warning: GOOGLE_APPLICATION_CREDENTIALS not set. Using gcloud application-default credentials...${NC}"
  # Try to get application default credentials
  gcloud_creds="${HOME}/.config/gcloud/application_default_credentials.json"
  if [ -f "$gcloud_creds" ]; then
    kubectl create secret generic gcp-storage-credentials \
      --from-file=credentials.json="$gcloud_creds" \
      --namespace=trino \
      --dry-run=client -o yaml | kubectl apply -f -
  else
    echo -e "${RED}Error: No GCP credentials found. Please run 'gcloud auth application-default login'${NC}"
    exit 1
  fi
fi

# Render Trino ConfigMap with VCI and GCP project
temp_configmap=$(mktemp)
sed "s|<VCI>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g; s|<GCP_PROJECT>|${GCP_PROJECT}|g" \
  "${SCRIPT_DIR}/k8s/configmap-gcp.yaml" > "$temp_configmap"
kubectl apply -f "$temp_configmap"
rm -f "$temp_configmap"

# Render Trino Deployment with GCP project
temp_deployment=$(mktemp)
sed "s|<GCP_PROJECT>|${GCP_PROJECT}|g" \
  "${SCRIPT_DIR}/k8s/deployment-gcp.yaml" > "$temp_deployment"
kubectl apply -f "$temp_deployment"
rm -f "$temp_deployment"

# Deploy Service
kubectl apply -f "${SCRIPT_DIR}/k8s/service.yaml"

echo -e "${CYAN}Waiting for Trino to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=trino -n trino --timeout=180s || true

echo -e "${GREEN}✓ Trino deployed successfully for GCP GCS backend${NC}"
