#!/bin/bash
# Module: Terraform Resources Destruction
# Step 4/6 of demo cleanup

run_step_destroy_terraform() {
  echo -e "${YELLOW}[4/6] Destroying Terraform resources...${NC}"

  # Always destroy WarpStream cluster
  terraform_destroy_if_exists "$WARPSTREAM_TF_DIR" "WarpStream" || true

  # Only destroy Azure resources if Terraform state exists
  if [ -d "${AZURE_TF_DIR}/.terraform" ] || [ -f "${AZURE_TF_DIR}/terraform.tfstate" ]; then
    # Check which resources are managed by Terraform by looking at state
    if [ -f "${AZURE_TF_DIR}/terraform.tfstate" ]; then
      pushd "${AZURE_TF_DIR}" >/dev/null
      terraform init -input=false >/dev/null 2>&1 || true

      local rg_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "azurerm_resource_group" and .name == "ws") | .address' || echo "")
      local sa_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "azurerm_storage_account" and .name == "ws") | .address' || echo "")
      local container_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "azurerm_storage_data_lake_gen2_filesystem" and .name == "tableflow") | .address' || echo "")

      if [ -z "$rg_in_state" ]; then
        echo -e "${YELLOW}Resource group not managed by Terraform${NC}"
        export AZURE_CREATE_RESOURCE_GROUP="false"
      else
        export AZURE_CREATE_RESOURCE_GROUP="true"
      fi

      if [ -z "$sa_in_state" ]; then
        echo -e "${YELLOW}Storage account not managed by Terraform${NC}"
        export AZURE_CREATE_STORAGE_ACCOUNT="false"
      else
        export AZURE_CREATE_STORAGE_ACCOUNT="true"
      fi

      if [ -z "$container_in_state" ]; then
        echo -e "${YELLOW}Container not managed by Terraform${NC}"
        export AZURE_CREATE_CONTAINER="false"
      else
        export AZURE_CREATE_CONTAINER="true"
      fi

      popd >/dev/null
    fi
    terraform_destroy_if_exists "$AZURE_TF_DIR" "Azure" || true
  else
    echo -e "${YELLOW}No Azure Terraform state found, skipping Azure resources destruction${NC}"
  fi
}
