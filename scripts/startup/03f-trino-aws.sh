#!/bin/bash

################################################################################
# Script: 03f-trino-aws.sh
# Description: Deploy Trino query engine for AWS S3 backend
################################################################################

run_step_trino_aws() {
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Step: Deploy Trino Query Engine (AWS S3)${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Verify AWS credentials are available
  if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
    echo -e "${YELLOW}Warning: AWS credentials not found in environment${NC}"
    echo -e "${CYAN}Re-checking AWS authentication...${NC}"

    # Re-source AWS helpers and validate credentials
    source "${SCRIPT_DIR}/scripts/common/aws.sh"
    validate_aws_credentials

    # Verify credentials are now set
    if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
      echo -e "${RED}Error: Unable to obtain AWS credentials${NC}"
      exit 1
    fi
  fi

  # Get WarpStream agent key if not already set
  if [ -z "${WARPSTREAM_AGENT_KEY:-}" ]; then
    source "${SCRIPT_DIR}/scripts/common/terraform.sh"
    export WARPSTREAM_AGENT_KEY="$(terraform_output_raw "${WARPSTREAM_TF_DIR:-${SCRIPT_DIR}/environment/warpstream/cluster}" "tableflow_agent_key")"
  fi

  # Export all required variables explicitly for child process
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_SESSION_TOKEN
  export AWS_REGION
  export WARPSTREAM_VIRTUAL_CLUSTER_ID
  export WARPSTREAM_AGENT_KEY

  local trino_deploy_script="${SCRIPT_DIR}/environment/trino/deploy-aws.sh"

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
