#!/bin/bash

################################################################################
# Script: demo-startup.sh
# Description: End-to-end setup for CFK + Confluent + Azure + WarpStream agent
# Usage: ./demo-startup.sh
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

########################################
# Source common modules
########################################

source "${SCRIPT_DIR}/scripts/common/colors.sh"
source "${SCRIPT_DIR}/scripts/common/utils.sh"
source "${SCRIPT_DIR}/scripts/common/regions.sh"
source "${SCRIPT_DIR}/scripts/common/aws.sh"
source "${SCRIPT_DIR}/scripts/common/azure.sh"
source "${SCRIPT_DIR}/scripts/common/gcp.sh"
source "${SCRIPT_DIR}/scripts/common/terraform.sh"
source "${SCRIPT_DIR}/scripts/common/warpstream.sh"

########################################
# Configuration
########################################

CONFLUENT_NAMESPACE="${CONFLUENT_NAMESPACE:-confluent}"
CONFLUENT_CR_FILE="${SCRIPT_DIR}/environment/confluent-platform/cp.yaml"

CFK_RELEASE="${CFK_RELEASE:-confluent-operator}"
CFK_NAMESPACE="${CFK_NAMESPACE:-confluent}"
CFK_HELM_REPO_NAME="${CFK_HELM_REPO_NAME:-confluentinc}"
CFK_HELM_REPO_URL="${CFK_HELM_REPO_URL:-https://packages.confluent.io/helm}"
CFK_HELM_CHART="${CFK_HELM_CHART:-confluentinc/confluent-for-kubernetes}"
CFK_ROLLOUT_TIMEOUT="${CFK_ROLLOUT_TIMEOUT:-300s}"
CP_READY_TIMEOUT="${CP_READY_TIMEOUT:-900s}"

AZURE_TF_DIR="${SCRIPT_DIR}/environment/azure"
WARPSTREAM_TF_DIR="${SCRIPT_DIR}/environment/warpstream/cluster"

WARPSTREAM_TEMPLATE_FILE="${SCRIPT_DIR}/environment/warpstream/agent/warpstream-agent-azure-template.yaml"
WARPSTREAM_AGENT_FILE="${SCRIPT_DIR}/environment/warpstream/agent/warpstream-agent.yaml"

DATAGEN_CONNECTOR_FILE="${SCRIPT_DIR}/environment/confluent-platform/datagen-connector.yaml"

TABLEFLOW_PIPELINE_TF_DIR="${SCRIPT_DIR}/environment/warpstream/tableflow-pipeline"
TABLEFLOW_PIPELINE_TEMPLATE="${TABLEFLOW_PIPELINE_TF_DIR}/orders-tableflow-pipeline-template.yaml"
TABLEFLOW_PIPELINE_FILE="${TABLEFLOW_PIPELINE_TF_DIR}/orders-tableflow-pipeline.yaml"
WARPSTREAM_NAMESPACE="${WARPSTREAM_NAMESPACE:-warpstream}"
WARPSTREAM_HELM_RELEASE="${WARPSTREAM_HELM_RELEASE:-warpstream-agent}"
WARPSTREAM_HELM_REPO_NAME="${WARPSTREAM_HELM_REPO_NAME:-warpstreamlabs}"
WARPSTREAM_HELM_REPO_URL="${WARPSTREAM_HELM_REPO_URL:-https://warpstreamlabs.github.io/charts}"
WARPSTREAM_HELM_CHART="${WARPSTREAM_HELM_CHART:-warpstreamlabs/warpstream-agent}"

CLOUD_PROVIDER="${CLOUD_PROVIDER:-}"
TABLEFLOW_REGION="${TABLEFLOW_REGION:-}"
WARPSTREAM_DEPLOY_API_KEY="${WARPSTREAM_DEPLOY_API_KEY:-${WARPSTREAM_API_KEY:-}}"
WARPSTREAM_AGENT_KEY_OVERRIDE="${WARPSTREAM_AGENT_KEY:-}"
TABLEFLOW_BACKEND="${TABLEFLOW_BACKEND:-}"
MINIO_NAMESPACE="${MINIO_NAMESPACE:-minio}"
MINIO_CONSOLE_PORT="${MINIO_CONSOLE_PORT:-9001}"
CONTROL_CENTER_PORT="${CONTROL_CENTER_PORT:-9021}"
TRINO_UI_PORT="${TRINO_UI_PORT:-8080}"

########################################
# Source startup step modules
########################################

source "${SCRIPT_DIR}/scripts/startup/01-cfk.sh"
source "${SCRIPT_DIR}/scripts/startup/02-confluent.sh"
source "${SCRIPT_DIR}/scripts/startup/03-datagen.sh"
source "${SCRIPT_DIR}/scripts/startup/03b-minio.sh"
source "${SCRIPT_DIR}/scripts/startup/03c-trino.sh"
source "${SCRIPT_DIR}/scripts/startup/03d-aws.sh"
source "${SCRIPT_DIR}/scripts/startup/03e-gcp.sh"
source "${SCRIPT_DIR}/scripts/startup/03f-trino-aws.sh"
source "${SCRIPT_DIR}/scripts/startup/03g-trino-gcp.sh"
source "${SCRIPT_DIR}/scripts/startup/04-terraform.sh"
source "${SCRIPT_DIR}/scripts/startup/05-warpstream-agent.sh"
source "${SCRIPT_DIR}/scripts/startup/06-tableflow-pipeline.sh"

########################################
# Main execution
########################################

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Run Demo: CFK + Confluent + WarpStream Tableflow${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

require_cmd kubectl
require_cmd helm
require_cmd terraform

# Cloud-specific CLI requirements checked during provider selection

validate_paths "$CONFLUENT_CR_FILE"
validate_paths "$WARPSTREAM_TF_DIR"
validate_paths "$DATAGEN_CONNECTOR_FILE"
validate_paths "$TABLEFLOW_PIPELINE_TF_DIR"
validate_paths "$TABLEFLOW_PIPELINE_TEMPLATE"

echo -e "${GREEN}✓ Prerequisites validated${NC}\n"

# Prompt for cloud provider, region, and backend
prompt_cloud_provider
prompt_region "$CLOUD_PROVIDER"
prompt_tableflow_backend "$CLOUD_PROVIDER"

# Prompt for WarpStream API key if not set
prompt_warpstream_api_key

# Execute common steps
run_step_cfk
run_step_confluent
run_step_datagen

# Conditionally deploy backend storage based on selections
if [ "${TABLEFLOW_BACKEND}" = "cloud" ]; then
  case "$CLOUD_PROVIDER" in
    aws)
      require_cmd aws
      run_step_aws
      ;;
    azure)
      require_cmd az
      run_step_terraform  # Azure uses existing terraform step
      ;;
    gcp)
      require_cmd gcloud
      run_step_gcp
      ;;
  esac
elif [ "${TABLEFLOW_BACKEND}" = "minio" ]; then
  run_step_minio
fi

# Deploy WarpStream cluster and agent (must be before Trino - provides WARPSTREAM_VIRTUAL_CLUSTER_ID)
run_step_terraform  # This now uses CLOUD_PROVIDER and TABLEFLOW_REGION variables

# Export WarpStream cluster ID for Trino and other components
export WARPSTREAM_VIRTUAL_CLUSTER_ID="$(terraform_output_raw "$WARPSTREAM_TF_DIR" "tableflow_virtual_cluster_id")"
echo -e "${GREEN}✓ WarpStream Virtual Cluster ID: ${WARPSTREAM_VIRTUAL_CLUSTER_ID}${NC}"

run_step_warpstream_agent

# Deploy query engine after WarpStream cluster is created
if [ "${TABLEFLOW_BACKEND}" = "cloud" ]; then
  case "$CLOUD_PROVIDER" in
    aws)
      run_step_trino_aws
      ;;
    azure)
      # Note: No Trino for Azure - azblob:// URI incompatibility
      ;;
    gcp)
      run_step_trino_gcp
      ;;
  esac
elif [ "${TABLEFLOW_BACKEND}" = "minio" ]; then
  run_step_trino
fi

# Deploy Tableflow pipeline
run_step_tableflow_pipeline

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Demo Deployment Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

backend_type="${TABLEFLOW_BACKEND:-azure}"
cloud_provider="${CLOUD_PROVIDER:-}"

if [ "$backend_type" = "minio" ]; then
  echo -e "${YELLOW}📊 Web UIs (automatically port-forwarded):${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "  🎛️  Confluent Control Center: ${GREEN}http://localhost:${CONTROL_CENTER_PORT}${NC}"
  echo "     Monitor Kafka topics, connectors, and data flow"
  echo
  echo -e "  📦 MinIO Console:             ${GREEN}http://localhost:${MINIO_CONSOLE_PORT}${NC}"
  echo "     Username: minioadmin | Password: minioadmin"
  echo "     Browse Iceberg tables and Parquet files"
  echo
  echo -e "  🔍 Trino Query UI:            ${GREEN}http://localhost:${TRINO_UI_PORT}${NC}"
  echo "     View query history and performance metrics"
  echo
  echo -e "${YELLOW}🧪 Test Trino Queries:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  # Show available catalogs and tables"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute 'SHOW TABLES FROM iceberg.default'"
  echo
  echo "  # Count total orders"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute \\"
  echo "    'SELECT COUNT(*) FROM iceberg.default.\"cp_cluster__datagen-orders\"'"
  echo
  echo "  # View sample orders"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute \\"
  echo "    'SELECT orderid, itemid, orderunits, address.city, address.state FROM iceberg.default.\"cp_cluster__datagen-orders\" LIMIT 10'"
  echo
  echo "  # Top states by order count"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute \\"
  echo "    'SELECT address.state, COUNT(*) as orders FROM iceberg.default.\"cp_cluster__datagen-orders\" GROUP BY address.state ORDER BY orders DESC LIMIT 5'"
  echo
  echo "  # Interactive Trino CLI"
  echo "  kubectl exec -it -n trino deployment/trino -- trino"
  echo
  echo -e "${YELLOW}⏱️  Time Travel Queries:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  # Unified query interface (auto-detects query engine)"
  echo "  ./demo-query.sh time-travel"
  echo
  echo "  # Interactive menu"
  echo "  ./demo-query.sh"
  echo
  echo -e "${YELLOW}📝 Configuration:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Backend:              MinIO (S3-compatible)"
  echo "  MinIO bucket:         ${MINIO_BUCKET:-tableflow}"
  echo "  MinIO endpoint:       ${MINIO_ENDPOINT:-http://minio.minio.svc.cluster.local:9000}"
  echo "  Trino filesystem:     Hadoop S3A"
  echo "  WarpStream VCI:       ${WARPSTREAM_VIRTUAL_CLUSTER_ID:-[not set]}"
  echo "  Confluent namespace:  ${CONFLUENT_NAMESPACE}"
  echo "  WarpStream namespace: ${WARPSTREAM_NAMESPACE}"
  echo "  Trino namespace:      trino"
elif [ "$backend_type" = "cloud" ] && [ "$cloud_provider" = "aws" ]; then
  echo -e "${YELLOW}📊 Web UIs (automatically port-forwarded):${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "  🎛️  Confluent Control Center: ${GREEN}http://localhost:${CONTROL_CENTER_PORT}${NC}"
  echo "     Monitor Kafka topics, connectors, and data flow"
  echo
  echo -e "  📦 AWS S3 Console:            ${GREEN}https://s3.console.aws.amazon.com/s3/buckets/${AWS_BUCKET_NAME}${NC}"
  echo "     Browse Iceberg tables and Parquet files in S3"
  echo
  echo -e "  🔍 Trino Query UI:            ${GREEN}http://localhost:${TRINO_UI_PORT}${NC}"
  echo "     View query history and performance metrics"
  echo
  echo -e "${YELLOW}🧪 Test Trino Queries:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  # Show available catalogs and tables"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute 'SHOW TABLES FROM iceberg.default'"
  echo
  echo "  # Count total orders"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute \\"
  echo "    'SELECT COUNT(*) FROM iceberg.default.\"cp_cluster__datagen-orders\"'"
  echo
  echo "  # View sample orders"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute \\"
  echo "    'SELECT orderid, itemid, orderunits, address.city, address.state FROM iceberg.default.\"cp_cluster__datagen-orders\" LIMIT 10'"
  echo
  echo "  # Top states by order count"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute \\"
  echo "    'SELECT address.state, COUNT(*) as orders FROM iceberg.default.\"cp_cluster__datagen-orders\" GROUP BY address.state ORDER BY orders DESC LIMIT 5'"
  echo
  echo "  # Interactive Trino CLI"
  echo "  kubectl exec -it -n trino deployment/trino -- trino"
  echo
  echo -e "${YELLOW}⏱️  Time Travel Queries:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  # Unified query interface (auto-detects query engine)"
  echo "  ./demo-query.sh time-travel"
  echo
  echo "  # Interactive menu"
  echo "  ./demo-query.sh"
  echo
  echo -e "${YELLOW}📝 Configuration:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Backend:              AWS S3"
  echo "  AWS Region:           ${AWS_REGION:-[not set]}"
  echo "  S3 Bucket:            ${AWS_BUCKET_NAME:-[not set]}"
  echo "  Trino filesystem:     Native S3"
  echo "  WarpStream VCI:       ${WARPSTREAM_VIRTUAL_CLUSTER_ID:-[not set]}"
  echo "  Confluent namespace:  ${CONFLUENT_NAMESPACE}"
  echo "  WarpStream namespace: ${WARPSTREAM_NAMESPACE}"
  echo "  Trino namespace:      trino"
elif [ "$backend_type" = "cloud" ] && [ "$cloud_provider" = "gcp" ]; then
  echo -e "${YELLOW}📊 Web UIs (automatically port-forwarded):${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "  🎛️  Confluent Control Center: ${GREEN}http://localhost:${CONTROL_CENTER_PORT}${NC}"
  echo "     Monitor Kafka topics, connectors, and data flow"
  echo
  echo -e "  📦 GCS Console:               ${GREEN}https://console.cloud.google.com/storage/browser/${GCP_BUCKET_NAME}${NC}"
  echo "     Browse Iceberg tables and Parquet files in GCS"
  echo
  echo -e "  🔍 Trino Query UI:            ${GREEN}http://localhost:${TRINO_UI_PORT}${NC}"
  echo "     View query history and performance metrics"
  echo
  echo -e "${YELLOW}🧪 Test Trino Queries:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  # Show available catalogs and tables"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute 'SHOW TABLES FROM iceberg.default'"
  echo
  echo "  # Count total orders"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute \\"
  echo "    'SELECT COUNT(*) FROM iceberg.default.\"cp_cluster__datagen-orders\"'"
  echo
  echo "  # View sample orders"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute \\"
  echo "    'SELECT orderid, itemid, orderunits, address.city, address.state FROM iceberg.default.\"cp_cluster__datagen-orders\" LIMIT 10'"
  echo
  echo "  # Top states by order count"
  echo "  kubectl exec -n trino deployment/trino -- trino --execute \\"
  echo "    'SELECT address.state, COUNT(*) as orders FROM iceberg.default.\"cp_cluster__datagen-orders\" GROUP BY address.state ORDER BY orders DESC LIMIT 5'"
  echo
  echo "  # Interactive Trino CLI"
  echo "  kubectl exec -it -n trino deployment/trino -- trino"
  echo
  echo -e "${YELLOW}⏱️  Time Travel Queries:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  # Unified query interface (auto-detects query engine)"
  echo "  ./demo-query.sh time-travel"
  echo
  echo "  # Interactive menu"
  echo "  ./demo-query.sh"
  echo
  echo -e "${YELLOW}📝 Configuration:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Backend:              GCP Cloud Storage (GCS)"
  echo "  GCP Project:          ${GCP_PROJECT:-[not set]}"
  echo "  GCP Region:           ${GCP_REGION:-[not set]}"
  echo "  GCS Bucket:           ${GCP_BUCKET_NAME:-[not set]}"
  echo "  Trino filesystem:     Native GCS"
  echo "  WarpStream VCI:       ${WARPSTREAM_VIRTUAL_CLUSTER_ID:-[not set]}"
  echo "  Confluent namespace:  ${CONFLUENT_NAMESPACE}"
  echo "  WarpStream namespace: ${WARPSTREAM_NAMESPACE}"
  echo "  Trino namespace:      trino"
else
  # Default to Azure
  echo -e "${YELLOW}📊 Web UIs (automatically port-forwarded):${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "  🎛️  Confluent Control Center: ${GREEN}http://localhost:${CONTROL_CENTER_PORT}${NC}"
  echo "     Monitor Kafka topics, connectors, and data flow"
  echo
  echo -e "  📦 Azure Storage Console:     ${GREEN}https://portal.azure.com/#view/Microsoft_Azure_Storage/ContainerMenuBlade/~/overview/storageAccountId/%2Fsubscriptions%2F${AZURE_SUBSCRIPTION_ID}%2FresourceGroups%2F${AZURE_RESOURCE_GROUP}%2Fproviders%2FMicrosoft.Storage%2FstorageAccounts%2F${AZURE_STORAGE_ACCOUNT}/path/${TABLEFLOW_CONTAINER}/etag/%22${NC}"
  echo "     Browse Iceberg tables and Parquet files in Azure Storage"
  echo
  echo -e "${YELLOW}📝 Configuration:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Backend:              Azure ADLS Gen2"
  echo "  Azure Region:         ${AZURE_REGION:-[not set]}"
  echo "  Storage account:      ${AZURE_STORAGE_ACCOUNT:-[not set]}"
  echo "  Container:            ${TABLEFLOW_CONTAINER:-[not set]}"
  echo "  Resource group:       ${AZURE_RESOURCE_GROUP:-[not set]}"
  echo "  WarpStream VCI:       ${WARPSTREAM_VIRTUAL_CLUSTER_ID:-[not set]}"
  echo "  Confluent namespace:  ${CONFLUENT_NAMESPACE}"
  echo "  WarpStream namespace: ${WARPSTREAM_NAMESPACE}"
  echo
  echo -e "${YELLOW}Note:${NC} Trino query engine is only available with AWS, GCP, and MinIO backends."
  echo "      Azure backend uses azblob:// URIs which are not compatible with Trino/Hadoop."
fi
echo

if [ -z "${WARPSTREAM_DEPLOY_API_KEY:-}" ] && [ -z "${WARPSTREAM_API_KEY:-}" ]; then
  echo
  echo -e "${YELLOW}Note:${NC} Export a deploy API key before running:"
  echo "  export WARPSTREAM_DEPLOY_API_KEY='<your_warpstream_account_api_key>'"
fi

if [ -z "${WARPSTREAM_AGENT_KEY_OVERRIDE:-}" ]; then
  echo -e "${YELLOW}Info:${NC} Agent key will be created/read from Terraform output (resource: warpstream_agent_key.demo_agent_key)."
else
  echo -e "${YELLOW}Info:${NC} Agent key override was used from WARPSTREAM_AGENT_KEY."
fi
