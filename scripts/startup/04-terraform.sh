#!/bin/bash
# Module: Terraform Resources (Azure + WarpStream)
# Step 4/6 of demo startup

run_step_terraform() {
  echo -e "${YELLOW}[4/6] Applying Terraform resources only when needed...${NC}"
  ensure_azure_login
  ensure_required_env_vars
  terraform_apply_if_needed "$AZURE_TF_DIR" "Azure"
  terraform_apply_if_needed "$WARPSTREAM_TF_DIR" "WarpStream"
  echo
}
