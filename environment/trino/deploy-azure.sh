#!/bin/bash

################################################################################
# Script: deploy-azure.sh
# Description: Deploy Trino with Azure Blob Storage (ABFSS) support
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common functions
source "${PROJECT_ROOT}/scripts/common/colors.sh"

echo -e "${CYAN}Deploying Trino for Azure Blob Storage backend...${NC}"

# Check required variables
if [ -z "${WARPSTREAM_VIRTUAL_CLUSTER_ID:-}" ]; then
  echo -e "${RED}Error: WARPSTREAM_VIRTUAL_CLUSTER_ID is not set${NC}"
  exit 1
fi

if [ -z "${WARPSTREAM_AGENT_KEY:-}" ]; then
  echo -e "${RED}Error: WARPSTREAM_AGENT_KEY is not set${NC}"
  echo -e "${YELLOW}This should be exported by demo-startup.sh${NC}"
  exit 1
fi

if [ -z "${TABLEFLOW_REGION:-}" ]; then
  echo -e "${RED}Error: TABLEFLOW_REGION is not set${NC}"
  exit 1
fi

# Get Azure storage credentials from Terraform outputs
echo -e "${CYAN}Retrieving Azure storage credentials from Terraform...${NC}"
cd "${PROJECT_ROOT}/environment/azure"

AZURE_STORAGE_ACCOUNT=$(terraform output -raw storage_account_name 2>/dev/null)
AZURE_STORAGE_KEY=$(terraform output -raw storage_account_primary_access_key 2>/dev/null)

if [ -z "${AZURE_STORAGE_ACCOUNT}" ] || [ -z "${AZURE_STORAGE_KEY}" ]; then
  echo -e "${RED}Error: Could not retrieve Azure storage credentials from Terraform${NC}"
  echo -e "${YELLOW}Make sure you have run 'terraform apply' in environment/azure${NC}"
  exit 1
fi

cd "${PROJECT_ROOT}"

# Create namespace
kubectl apply -f "${SCRIPT_DIR}/k8s/namespace.yaml"

# Create WarpStream agent API key secret for proxy
echo -e "${CYAN}Creating WarpStream agent API key secret...${NC}"
kubectl create secret generic warpstream-agent-apikey \
  --from-literal=apikey="${WARPSTREAM_AGENT_KEY:-}" \
  --namespace=trino \
  --dry-run=client -o yaml | kubectl apply -f -

# Determine WarpStream metadata URL based on Azure region
# Azure uses a different URL format: metadata.default.{region}.azure.warpstream.com
METADATA_URL="metadata.default.${TABLEFLOW_REGION}.azure.warpstream.com"
echo -e "${CYAN}Using WarpStream metadata URL: ${METADATA_URL}${NC}"

# Deploy WarpStream proxy (for REST catalog auth) with correct metadata URL
temp_proxy_config=$(mktemp)
sed "s|<METADATA_URL>|${METADATA_URL}|g" \
  "${SCRIPT_DIR}/k8s/proxy-configmap.yaml" > "$temp_proxy_config"
kubectl apply -f "$temp_proxy_config"
rm -f "$temp_proxy_config"

kubectl apply -f "${SCRIPT_DIR}/k8s/proxy-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/proxy-service.yaml"

# Create Azure storage credentials secret in trino namespace
echo -e "${CYAN}Creating Azure storage credentials secret in trino namespace...${NC}"
kubectl create secret generic azure-storage-credentials \
  --from-literal=storage-account-name="${AZURE_STORAGE_ACCOUNT}" \
  --from-literal=storage-account-key="${AZURE_STORAGE_KEY}" \
  --namespace=trino \
  --dry-run=client -o yaml | kubectl apply -f -

# Render Trino ConfigMap with VCI and Azure Storage Key
temp_configmap=$(mktemp)
sed "s|<VCI>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g; s|<AZURE_STORAGE_KEY>|${AZURE_STORAGE_KEY}|g" \
  "${SCRIPT_DIR}/k8s/configmap-azure.yaml" > "$temp_configmap"
kubectl apply -f "$temp_configmap"
rm -f "$temp_configmap"

# Deploy Trino Deployment
kubectl apply -f "${SCRIPT_DIR}/k8s/deployment-azure.yaml"

# Deploy Service
kubectl apply -f "${SCRIPT_DIR}/k8s/service.yaml"

echo -e "${CYAN}Waiting for Trino to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=trino -n trino --timeout=180s || true

echo -e "${GREEN}✓ Trino deployed successfully for Azure Blob Storage backend${NC}"
echo -e "${CYAN}Storage Account: ${AZURE_STORAGE_ACCOUNT}${NC}"
echo -e "${CYAN}Using ABFSS protocol for Azure Data Lake Storage Gen2${NC}"
