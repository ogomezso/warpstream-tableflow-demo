#!/bin/bash
# Module: Terraform Resources (Azure + WarpStream)
# Step 4/6 of demo startup

run_step_terraform() {
  echo -e "${YELLOW}[4/7] Applying Terraform resources only when needed...${NC}"

  # Conditionally apply Azure resources if using Azure backend
  # Legacy mode: TABLEFLOW_BACKEND="azure" or not set
  # New mode: TABLEFLOW_BACKEND="cloud" and CLOUD_PROVIDER="azure"
  local should_apply_azure=false
  if [ "${TABLEFLOW_BACKEND:-azure}" = "azure" ]; then
    should_apply_azure=true
  elif [ "${TABLEFLOW_BACKEND}" = "cloud" ] && [ "${CLOUD_PROVIDER:-}" = "azure" ]; then
    should_apply_azure=true
  fi

  if [ "$should_apply_azure" = "true" ]; then
    ensure_azure_login
    prompt_azure_resource_group
    prompt_azure_storage_account
    prompt_azure_container

    # Safety checks: if using existing resources but they're in Terraform state, remove them from state
    if [ -f "${AZURE_TF_DIR}/terraform.tfstate" ]; then
      pushd "${AZURE_TF_DIR}" >/dev/null
      terraform init -input=false >/dev/null 2>&1 || true

      # Check resource group
      if [ "${AZURE_CREATE_RESOURCE_GROUP}" = "false" ]; then
        local rg_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "azurerm_resource_group" and .name == "ws") | .address' || echo "")
        if [ -n "$rg_in_state" ]; then
          echo -e "${YELLOW}⚠️  Resource group is in Terraform state but you selected 'use existing'${NC}"
          echo -e "${YELLOW}Removing from state to prevent accidental destruction...${NC}"
          terraform state rm "$rg_in_state" >/dev/null 2>&1 || true
          echo -e "${GREEN}✓ Resource group removed from Terraform state${NC}"
        fi
      fi

      # Check storage account
      if [ "${AZURE_CREATE_STORAGE_ACCOUNT}" = "false" ]; then
        local sa_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "azurerm_storage_account" and .name == "ws") | .address' || echo "")
        if [ -n "$sa_in_state" ]; then
          echo -e "${YELLOW}⚠️  Storage account is in Terraform state but you selected 'use existing'${NC}"
          echo -e "${YELLOW}Removing from state to prevent accidental destruction...${NC}"
          terraform state rm "$sa_in_state" >/dev/null 2>&1 || true
          echo -e "${GREEN}✓ Storage account removed from Terraform state${NC}"
        fi
      fi

      # Check container
      if [ "${AZURE_CREATE_CONTAINER}" = "false" ]; then
        local container_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "azurerm_storage_data_lake_gen2_filesystem" and .name == "tableflow") | .address' || echo "")
        if [ -n "$container_in_state" ]; then
          echo -e "${YELLOW}⚠️  Container is in Terraform state but you selected 'use existing'${NC}"
          echo -e "${YELLOW}Removing from state to prevent accidental destruction...${NC}"
          terraform state rm "$container_in_state" >/dev/null 2>&1 || true
          echo -e "${GREEN}✓ Container removed from Terraform state${NC}"
        fi
      fi

      popd >/dev/null
    fi

    terraform_apply_if_needed "$AZURE_TF_DIR" "Azure"
  else
    echo -e "${YELLOW}Skipping Azure resources (using ${TABLEFLOW_BACKEND:-azure} backend with ${CLOUD_PROVIDER:-none} provider)${NC}"
  fi

  # Conditionally apply GCP resources if using GCP backend
  local should_apply_gcp=false
  if [ "${TABLEFLOW_BACKEND}" = "cloud" ] && [ "${CLOUD_PROVIDER:-}" = "gcp" ]; then
    should_apply_gcp=true
  fi

  if [ "$should_apply_gcp" = "true" ]; then
    # Validate GCP credentials
    source "${SCRIPT_DIR}/scripts/common/gcp.sh"
    validate_gcp_credentials

    # Prompt for bucket configuration
    prompt_gcp_bucket

    local gcp_tf_dir="${SCRIPT_DIR}/environment/gcp"

    # Safety check: if using existing bucket but it's in Terraform state, remove it from state
    if [ "${GCP_CREATE_BUCKET}" = "false" ] && [ -f "${gcp_tf_dir}/terraform.tfstate" ]; then
      pushd "${gcp_tf_dir}" >/dev/null
      terraform init -input=false >/dev/null 2>&1 || true

      local bucket_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "google_storage_bucket" and .name == "tableflow") | .address' || echo "")
      if [ -n "$bucket_in_state" ]; then
        echo -e "${YELLOW}⚠️  GCS bucket is in Terraform state but you selected 'use existing'${NC}"
        echo -e "${YELLOW}Removing from state to prevent accidental destruction...${NC}"
        terraform state rm "$bucket_in_state" >/dev/null 2>&1 || true
        echo -e "${GREEN}✓ GCS bucket removed from Terraform state${NC}"
      fi
      popd >/dev/null
    fi

    echo -e "${CYAN}Using GCP project: ${GCP_PROJECT}${NC}"
    echo -e "${CYAN}Using GCP region: ${GCP_REGION}${NC}"

    terraform_apply_if_needed "$gcp_tf_dir" "GCP GCS"

    # Get outputs (whether newly created or already existing)
    if [ -z "${GCP_BUCKET_NAME:-}" ]; then
      export GCP_BUCKET_NAME=$(terraform_output_raw "$gcp_tf_dir" "bucket_name")
    fi
    export GCP_BUCKET_URL=$(terraform_output_raw "$gcp_tf_dir" "bucket_url")

    echo -e "${GREEN}✓ GCP GCS bucket: ${GCP_BUCKET_NAME}${NC}"
    echo -e "${GREEN}✓ Bucket URL: ${GCP_BUCKET_URL}${NC}"
  else
    echo -e "${YELLOW}Skipping GCP resources (using ${TABLEFLOW_BACKEND:-azure} backend with ${CLOUD_PROVIDER:-none} provider)${NC}"
  fi

  # WarpStream cluster resources are always needed
  ensure_required_env_vars
  terraform_apply_if_needed "$WARPSTREAM_TF_DIR" "WarpStream"
  echo
}
