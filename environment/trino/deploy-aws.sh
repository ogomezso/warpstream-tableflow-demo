#!/bin/bash

################################################################################
# Script: deploy-aws.sh
# Description: Deploy Trino with AWS S3 native filesystem support
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# Source common functions
source "${PROJECT_ROOT}/scripts/common/colors.sh"

echo -e "${CYAN}Deploying Trino for AWS S3 backend...${NC}"

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

if [ -z "${AWS_REGION:-}" ]; then
  echo -e "${RED}Error: AWS_REGION is not set${NC}"
  exit 1
fi

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
  echo -e "${RED}Error: AWS credentials not found in environment${NC}"
  echo -e "${RED}AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY must be set${NC}"
  echo -e "${YELLOW}Hint: These should be set automatically by AWS SSO/granted assume${NC}"
  echo -e "${YELLOW}Try running: assume -ex (for Confluent employees)${NC}"
  echo -e "${YELLOW}Or configure AWS credentials: aws configure${NC}"
  exit 1
fi

# Create namespace
kubectl apply -f "${SCRIPT_DIR}/k8s/namespace.yaml"

# Create WarpStream agent API key secret for proxy
echo -e "${CYAN}Creating WarpStream agent API key secret...${NC}"
kubectl create secret generic warpstream-agent-apikey \
  --from-literal=apikey="${WARPSTREAM_AGENT_KEY:-}" \
  --namespace=trino \
  --dry-run=client -o yaml | kubectl apply -f -

# Determine WarpStream metadata URL based on AWS region
METADATA_URL="metadata.default.${AWS_REGION}.warpstream.com"
echo -e "${CYAN}Using WarpStream metadata URL: ${METADATA_URL}${NC}"

# Deploy WarpStream proxy (for REST catalog auth) with correct metadata URL
temp_proxy_config=$(mktemp)
sed "s|<METADATA_URL>|${METADATA_URL}|g" \
  "${SCRIPT_DIR}/k8s/proxy-configmap.yaml" > "$temp_proxy_config"
kubectl apply -f "$temp_proxy_config"
rm -f "$temp_proxy_config"

kubectl apply -f "${SCRIPT_DIR}/k8s/proxy-deployment.yaml"
kubectl apply -f "${SCRIPT_DIR}/k8s/proxy-service.yaml"

# Create AWS storage credentials secret in trino namespace
echo -e "${CYAN}Creating AWS credentials secret in trino namespace...${NC}"
kubectl create secret generic aws-storage-credentials \
  --from-literal=aws-access-key-id="${AWS_ACCESS_KEY_ID}" \
  --from-literal=aws-secret-access-key="${AWS_SECRET_ACCESS_KEY}" \
  --from-literal=aws-session-token="${AWS_SESSION_TOKEN:-}" \
  --namespace=trino \
  --dry-run=client -o yaml | kubectl apply -f -

# Render Trino ConfigMap with VCI and AWS region
temp_configmap=$(mktemp)
sed "s|<VCI>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g; s|<AWS_REGION>|${AWS_REGION}|g" \
  "${SCRIPT_DIR}/k8s/configmap-aws.yaml" > "$temp_configmap"
kubectl apply -f "$temp_configmap"
rm -f "$temp_configmap"

# Render Trino Deployment with AWS region
temp_deployment=$(mktemp)
sed "s|<AWS_REGION>|${AWS_REGION}|g" \
  "${SCRIPT_DIR}/k8s/deployment-aws.yaml" > "$temp_deployment"
kubectl apply -f "$temp_deployment"
rm -f "$temp_deployment"

# Deploy Service
kubectl apply -f "${SCRIPT_DIR}/k8s/service.yaml"

echo -e "${CYAN}Waiting for Trino to be ready...${NC}"
kubectl wait --for=condition=ready pod -l app=trino -n trino --timeout=180s || true

echo -e "${GREEN}✓ Trino deployed successfully for AWS S3 backend${NC}"
