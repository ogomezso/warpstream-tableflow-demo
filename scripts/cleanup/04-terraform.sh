#!/bin/bash
# Module: Terraform Resources Destruction
# Step 4/6 of demo cleanup

run_step_destroy_terraform() {
  echo -e "${YELLOW}[4/6] Destroying Terraform resources...${NC}"
  terraform_destroy_if_exists "$WARPSTREAM_TF_DIR" "WarpStream" || true
  terraform_destroy_if_exists "$AZURE_TF_DIR" "Azure" || true
}
