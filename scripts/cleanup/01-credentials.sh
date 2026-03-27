#!/bin/bash
# Module: Credential Validation
# Step 1/6 of demo cleanup

run_step_credentials() {
  echo -e "${YELLOW}[1/6] Validating credentials...${NC}"
  ensure_azure_login
  ensure_required_env_vars
}
