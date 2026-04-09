#!/bin/bash
# Module: Terraform Resources (Azure + WarpStream)
# Step 4/6 of demo startup

run_step_terraform() {
  echo -e "${YELLOW}[4/7] Applying Terraform resources only when needed...${NC}"

  # Conditionally apply Azure resources only if using Azure backend
  if [ "${TABLEFLOW_BACKEND:-azure}" = "azure" ]; then
    ensure_azure_login
    terraform_apply_if_needed "$AZURE_TF_DIR" "Azure"
  else
    echo -e "${YELLOW}Skipping Azure resources (using ${TABLEFLOW_BACKEND} backend)${NC}"
  fi

  # WarpStream cluster resources are always needed
  ensure_required_env_vars
  terraform_apply_if_needed "$WARPSTREAM_TF_DIR" "WarpStream"
  echo
}
