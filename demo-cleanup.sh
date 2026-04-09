#!/bin/bash

################################################################################
# Script: demo-cleanup.sh
# Description: Tear down resources/files created by demo-startup.sh
# Usage: ./demo-cleanup.sh
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
source "${SCRIPT_DIR}/scripts/common/kubernetes.sh"
source "${SCRIPT_DIR}/scripts/common/port-forward.sh"

########################################
# Configuration
########################################

CONFLUENT_NAMESPACE="${CONFLUENT_NAMESPACE:-confluent}"
CONFLUENT_CR_FILE="${SCRIPT_DIR}/environment/confluent-platform/cp.yaml"
DATAGEN_CONNECTOR_FILE="${SCRIPT_DIR}/environment/confluent-platform/datagen-connector.yaml"

CFK_RELEASE="${CFK_RELEASE:-confluent-operator}"
CFK_NAMESPACE="${CFK_NAMESPACE:-confluent}"
CLEANUP_REMOVE_CFK_OPERATOR="${CLEANUP_REMOVE_CFK_OPERATOR:-true}"

AZURE_TF_DIR="${SCRIPT_DIR}/environment/azure"
WARPSTREAM_TF_DIR="${SCRIPT_DIR}/environment/warpstream/cluster"
TABLEFLOW_PIPELINE_TF_DIR="${SCRIPT_DIR}/environment/warpstream/tableflow-pipeline"

WARPSTREAM_AGENT_FILE="${SCRIPT_DIR}/environment/warpstream/agent/warpstream-agent.yaml"
WARPSTREAM_NAMESPACE="${WARPSTREAM_NAMESPACE:-warpstream}"
WARPSTREAM_HELM_RELEASE="${WARPSTREAM_HELM_RELEASE:-warpstream-agent}"
NAMESPACE_DELETE_TIMEOUT_SECONDS="${NAMESPACE_DELETE_TIMEOUT_SECONDS:-30}"
MINIO_NAMESPACE="${MINIO_NAMESPACE:-minio}"

TABLEFLOW_PIPELINE_FILE="${SCRIPT_DIR}/environment/warpstream/tableflow-pipeline/orders-tableflow-pipeline.yaml"

WARPSTREAM_DEPLOY_API_KEY="${WARPSTREAM_DEPLOY_API_KEY:-${WARPSTREAM_API_KEY:-}}"

# Tracking arrays and flags
FAILURES=()
PENDING_NAMESPACES=()
TF_DESTROY_SUCCESS_WARPSTREAM=false
TF_DESTROY_SUCCESS_AZURE=false
TF_DESTROY_SUCCESS_TABLEFLOW_PIPELINE=false

########################################
# Source cleanup step modules
########################################

source "${SCRIPT_DIR}/scripts/cleanup/01-credentials.sh"
source "${SCRIPT_DIR}/scripts/cleanup/02-tableflow-pipeline.sh"
source "${SCRIPT_DIR}/scripts/cleanup/03-warpstream-k8s.sh"
source "${SCRIPT_DIR}/scripts/cleanup/03b-minio.sh"
source "${SCRIPT_DIR}/scripts/cleanup/03c-trino.sh"
source "${SCRIPT_DIR}/scripts/cleanup/04-terraform.sh"
source "${SCRIPT_DIR}/scripts/cleanup/05-confluent.sh"
source "${SCRIPT_DIR}/scripts/cleanup/06-cleanup-files.sh"

########################################
# Main execution
########################################

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Demo Cleanup: tear down demo-startup.sh resources${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

require_cmd kubectl
require_cmd helm
require_cmd terraform
require_cmd az

# Stop port-forwards first
echo -e "${YELLOW}Stopping port-forwards...${NC}"
stop_control_center_port_forward
stop_minio_console_port_forward
stop_trino_ui_port_forward
echo

# Execute steps
run_step_credentials
run_step_destroy_tableflow_pipeline
run_step_warpstream_k8s
run_step_cleanup_minio
run_step_cleanup_trino
run_step_destroy_terraform
run_step_confluent
run_step_cleanup_files

echo
if [ "${#FAILURES[@]}" -eq 0 ] && [ "${#PENDING_NAMESPACES[@]}" -eq 0 ]; then
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}Demo Cleanup Complete${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
elif [ "${#FAILURES[@]}" -eq 0 ]; then
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Demo Cleanup Complete (with pending namespace deletions)${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Warning: The following namespaces are still terminating:${NC}"
  for ns in "${PENDING_NAMESPACES[@]}"; do
    echo -e "${YELLOW}  - ${ns}${NC}"
  done
  echo -e "${YELLOW}Please verify these are fully deleted by running:${NC}"
  for ns in "${PENDING_NAMESPACES[@]}"; do
    echo "  kubectl get namespace ${ns}"
  done
else
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Demo Cleanup Completed With Failures${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo "Failures:"
  for failure in "${FAILURES[@]}"; do
    echo "- ${failure}"
  done
  if [ "${#PENDING_NAMESPACES[@]}" -gt 0 ]; then
    echo
    echo -e "${YELLOW}Warning: The following namespaces are still terminating:${NC}"
    for ns in "${PENDING_NAMESPACES[@]}"; do
      echo -e "${YELLOW}  - ${ns}${NC}"
    done
    echo -e "${YELLOW}Please verify these are fully deleted by running:${NC}"
    for ns in "${PENDING_NAMESPACES[@]}"; do
      echo "  kubectl get namespace ${ns}"
    done
  fi
  exit 1
fi
