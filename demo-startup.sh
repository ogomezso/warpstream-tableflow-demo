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

########################################
# Source startup step modules
########################################

source "${SCRIPT_DIR}/scripts/startup/01-cfk.sh"
source "${SCRIPT_DIR}/scripts/startup/02-confluent.sh"
source "${SCRIPT_DIR}/scripts/startup/03-datagen.sh"
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

# Execute steps
run_step_cfk
run_step_confluent
run_step_datagen
run_step_terraform
run_step_warpstream_agent
run_step_tableflow_pipeline

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Run Demo Complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo "Summary:"
echo "- Confluent namespace: ${CONFLUENT_NAMESPACE}"
echo "- CFK release: ${CFK_RELEASE}"
echo "- CFK namespace: ${CFK_NAMESPACE}"
echo "- Datagen connector: ${DATAGEN_CONNECTOR_FILE}"
echo "- Azure storage account: ${AZURE_STORAGE_ACCOUNT:-[not set]}"
echo "- Azure container: ${TABLEFLOW_CONTAINER:-[not set]}"
echo "- Bucket URL: ${BUCKET_URL:-[not set]}"
echo "- WarpStream virtual cluster ID: ${WARPSTREAM_VIRTUAL_CLUSTER_ID:-[not set]}"
echo "- WarpStream deploy key: [redacted]"
echo "- WarpStream agent key: [redacted]"
echo "- WarpStream namespace: ${WARPSTREAM_NAMESPACE}"
echo "- WarpStream Helm release: ${WARPSTREAM_HELM_RELEASE}"
echo "- WarpStream agent file: ${WARPSTREAM_AGENT_FILE}"
echo "- Tableflow pipeline: ${TABLEFLOW_PIPELINE_TF_DIR}"

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
