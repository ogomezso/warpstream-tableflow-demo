#!/bin/bash

################################################################################
# Script: 03e-gcp.sh
# Description: Deploy GCP GCS backend for WarpStream Tableflow
################################################################################

run_step_gcp() {
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Step: Deploy GCP GCS Backend${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Source GCP helper functions
  source "${SCRIPT_DIR}/scripts/common/gcp.sh"

  # Validate GCP credentials
  validate_gcp_credentials

  # Prompt for bucket configuration
  prompt_gcp_bucket

  # Set Terraform variables
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

  # Apply Terraform only if needed
  source "${SCRIPT_DIR}/scripts/common/terraform.sh"
  terraform_apply_if_needed "$gcp_tf_dir" "GCP GCS"

  # Get outputs (whether newly created or already existing)
  if [ -z "${GCP_BUCKET_NAME:-}" ]; then
    export GCP_BUCKET_NAME=$(terraform_output_raw "$gcp_tf_dir" "bucket_name")
  fi
  export GCP_BUCKET_URL=$(terraform_output_raw "$gcp_tf_dir" "bucket_url")

  echo -e "${GREEN}✓ GCP GCS bucket: ${GCP_BUCKET_NAME}${NC}"
  echo -e "${GREEN}✓ Bucket URL: ${GCP_BUCKET_URL}${NC}"
}
