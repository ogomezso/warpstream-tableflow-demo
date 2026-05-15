#!/bin/bash

################################################################################
# Script: 03h-trino-azure.sh
# Description: Deploy Trino query engine for Azure Blob Storage backend
################################################################################

run_step_trino_azure() {
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Step: Deploy Trino Query Engine (Azure Blob Storage)${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Get WarpStream agent key if not already set
  if [ -z "${WARPSTREAM_AGENT_KEY:-}" ]; then
    source "${SCRIPT_DIR}/scripts/common/terraform.sh"
    export WARPSTREAM_AGENT_KEY="$(terraform_output_raw "${WARPSTREAM_TF_DIR:-${SCRIPT_DIR}/environment/warpstream/cluster}" "tableflow_agent_key")"
  fi

  # Export required variables for child process
  export WARPSTREAM_VIRTUAL_CLUSTER_ID
  export WARPSTREAM_AGENT_KEY
  export TABLEFLOW_REGION

  local trino_deploy_script="${SCRIPT_DIR}/environment/trino/deploy-azure.sh"

  if [ ! -f "$trino_deploy_script" ]; then
    echo -e "${RED}Error: Trino deployment script not found: ${trino_deploy_script}${NC}"
    exit 1
  fi

  # Run Trino deployment
  bash "$trino_deploy_script"

  # Setup port-forward for Trino UI
  echo -e "${CYAN}Setting up port-forward for Trino UI...${NC}"
  source "${SCRIPT_DIR}/scripts/common/port-forward.sh"
  setup_trino_ui_port_forward

  echo -e "${GREEN}✓ Trino deployed successfully${NC}"
  echo -e "${GREEN}✓ Trino UI available at: http://localhost:${TRINO_UI_PORT}${NC}"
}
