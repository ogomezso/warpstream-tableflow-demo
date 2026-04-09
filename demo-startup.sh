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
source "${SCRIPT_DIR}/scripts/common/azure.sh"
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

WARPSTREAM_TEMPLATE_FILE="${SCRIPT_DIR}/environment/warpstream/agent/warpstream-agent-template.yaml"
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

TABLEFLOW_REGION="${TABLEFLOW_REGION:-eastus}"
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
require_cmd az

validate_paths "$CONFLUENT_CR_FILE"
validate_paths "$AZURE_TF_DIR"
validate_paths "$WARPSTREAM_TF_DIR"
validate_paths "$WARPSTREAM_TEMPLATE_FILE"
validate_paths "$DATAGEN_CONNECTOR_FILE"
validate_paths "$TABLEFLOW_PIPELINE_TF_DIR"
validate_paths "$TABLEFLOW_PIPELINE_TEMPLATE"

echo -e "${GREEN}✓ Prerequisites validated${NC}\n"

# Prompt for backend selection
prompt_tableflow_backend

# Execute steps
run_step_cfk
run_step_confluent
run_step_datagen

# Conditionally deploy backend storage and query engine
if [ "${TABLEFLOW_BACKEND}" = "minio" ]; then
  run_step_minio
  run_step_trino
fi

run_step_terraform
run_step_warpstream_agent
run_step_tableflow_pipeline

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Demo Deployment Complete!${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

if [ "${TABLEFLOW_BACKEND}" = "minio" ]; then
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
else
  echo -e "${YELLOW}📊 Web UI (automatically port-forwarded):${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo -e "  🎛️  Confluent Control Center: ${GREEN}http://localhost:${CONTROL_CENTER_PORT}${NC}"
  echo "     Monitor Kafka topics, connectors, and data flow"
  echo
  echo -e "${YELLOW}📝 Configuration:${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Backend:              Azure ADLS Gen2"
  echo "  Storage account:      ${AZURE_STORAGE_ACCOUNT:-[not set]}"
  echo "  Container:            ${TABLEFLOW_CONTAINER:-[not set]}"
  echo "  WarpStream VCI:       ${WARPSTREAM_VIRTUAL_CLUSTER_ID:-[not set]}"
  echo "  Confluent namespace:  ${CONFLUENT_NAMESPACE}"
  echo "  WarpStream namespace: ${WARPSTREAM_NAMESPACE}"
  echo
  echo -e "${YELLOW}Note:${NC} Trino query engine is only available with MinIO backend."
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
