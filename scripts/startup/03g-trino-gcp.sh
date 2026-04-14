#!/bin/bash

################################################################################
# Script: 03g-trino-gcp.sh
# Description: Deploy Trino query engine for GCP GCS backend
################################################################################

run_step_trino_gcp() {
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Step: Deploy Trino Query Engine (GCP GCS)${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local trino_deploy_script="${SCRIPT_DIR}/environment/trino/deploy-gcp.sh"

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
