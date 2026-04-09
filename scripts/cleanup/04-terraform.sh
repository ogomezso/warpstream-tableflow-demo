#!/bin/bash
# Module: Terraform Resources Destruction
# Step 4/6 of demo cleanup

run_step_destroy_terraform() {
  echo -e "${YELLOW}[4/6] Destroying Terraform resources...${NC}"

  # Always destroy WarpStream cluster
  terraform_destroy_if_exists "$WARPSTREAM_TF_DIR" "WarpStream" || true

  # Only destroy Azure resources if Terraform state exists
  if [ -d "${AZURE_TF_DIR}/.terraform" ] || [ -f "${AZURE_TF_DIR}/terraform.tfstate" ]; then
    terraform_destroy_if_exists "$AZURE_TF_DIR" "Azure" || true
  else
    echo -e "${YELLOW}No Azure Terraform state found, skipping Azure resources destruction${NC}"
  fi
}
