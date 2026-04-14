#!/bin/bash

################################################################################
# Script: 03e-gcp.sh
# Description: Cleanup GCP GCS backend resources
################################################################################

run_cleanup_gcp() {
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Cleanup: GCP GCS Backend${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local gcp_tf_dir="${SCRIPT_DIR}/environment/gcp"

  # Check if GCP Terraform state exists
  if [ ! -f "${gcp_tf_dir}/terraform.tfstate" ]; then
    echo -e "${CYAN}No GCP Terraform state found - skipping GCP cleanup${NC}"
    return 0
  fi

  # Check if bucket is managed by Terraform by looking at state
  if [ -f "${gcp_tf_dir}/terraform.tfstate" ]; then
    pushd "${gcp_tf_dir}" >/dev/null
    terraform init -input=false >/dev/null 2>&1 || true

    local bucket_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "google_storage_bucket" and .name == "tableflow") | .address' || echo "")
    if [ -z "$bucket_in_state" ]; then
      echo -e "${YELLOW}GCS bucket not managed by Terraform${NC}"
      export GCP_CREATE_BUCKET="false"
    else
      export GCP_CREATE_BUCKET="true"
    fi

    popd >/dev/null
  fi

  # Source GCP helper functions
  source "${SCRIPT_DIR}/scripts/common/gcp.sh"

  # Validate GCP credentials (only if state exists)
  echo -e "${CYAN}Validating GCP credentials...${NC}"
  authenticate_gcp

  # Get project from state if possible
  cd "$gcp_tf_dir" || exit 1

  if [ -f "terraform.tfstate" ]; then
    local project_from_state=$(terraform output -raw bucket_name 2>/dev/null | cut -d'-' -f1-4 || echo "")

    if [ -z "${GCP_PROJECT:-}" ] && [ -n "$project_from_state" ]; then
      # Try to extract project from state
      export GCP_PROJECT=$(grep -o '"project_id":\s*"[^"]*"' terraform.tfstate | head -1 | cut -d'"' -f4 || echo "")
    fi

    if [ -z "${GCP_PROJECT:-}" ]; then
      validate_gcp_project
    fi
  fi

  # Destroy GCP resources
  echo -e "${CYAN}Destroying GCP GCS bucket via Terraform...${NC}"

  # Set Terraform variables
  export TF_VAR_project_id="${GCP_PROJECT}"
  export TF_VAR_region="${GCP_REGION:-us-central1}"

  terraform init -upgrade
  terraform destroy -auto-approve

  # Clean up Terraform files
  rm -rf .terraform
  rm -f .terraform.lock.hcl
  rm -f terraform.tfstate*
  rm -f tfplan

  cd - > /dev/null

  echo -e "${GREEN}✓ GCP resources cleaned up${NC}"
}
