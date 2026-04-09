#!/bin/bash
# Module: Credential Validation
# Step 1/6 of demo cleanup

run_step_credentials() {
  echo -e "${YELLOW}[1/6] Validating credentials...${NC}"

  # Only validate Azure credentials if we're using Azure backend
  # Check if Azure Terraform state exists to determine backend
  if [ -d "${AZURE_TF_DIR}/.terraform" ] || [ -f "${AZURE_TF_DIR}/terraform.tfstate" ]; then
    echo "Azure Terraform state detected, validating Azure credentials..."
    ensure_azure_login
  else
    echo -e "${GREEN}No Azure Terraform state found, skipping Azure login${NC}"
  fi

  # WarpStream credentials are always needed for Terraform destroy
  ensure_required_env_vars
}
