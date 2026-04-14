#!/bin/bash

################################################################################
# Script: 03d-aws.sh
# Description: Deploy AWS S3 backend for WarpStream Tableflow
################################################################################

run_step_aws() {
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Step: Deploy AWS S3 Backend${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Source AWS helper functions
  source "${SCRIPT_DIR}/scripts/common/aws.sh"

  # Validate AWS credentials
  validate_aws_credentials

  # Prompt for bucket configuration
  prompt_aws_bucket

  # Set Terraform variables
  local aws_tf_dir="${SCRIPT_DIR}/environment/aws"

  # Safety check: if using existing bucket but it's in Terraform state, remove it from state
  if [ "${AWS_CREATE_BUCKET}" = "false" ] && [ -f "${aws_tf_dir}/terraform.tfstate" ]; then
    pushd "${aws_tf_dir}" >/dev/null
    terraform init -input=false >/dev/null 2>&1 || true

    local bucket_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "aws_s3_bucket" and .name == "tableflow") | .address' || echo "")
    if [ -n "$bucket_in_state" ]; then
      echo -e "${YELLOW}⚠️  S3 bucket is in Terraform state but you selected 'use existing'${NC}"
      echo -e "${YELLOW}Removing from state to prevent accidental destruction...${NC}"
      terraform state rm "$bucket_in_state" >/dev/null 2>&1 || true

      # Also remove dependent resources
      terraform state rm "aws_s3_bucket_versioning.tableflow" >/dev/null 2>&1 || true
      terraform state rm "aws_s3_bucket_server_side_encryption_configuration.tableflow" >/dev/null 2>&1 || true
      terraform state rm "aws_s3_bucket_public_access_block.tableflow" >/dev/null 2>&1 || true
      terraform state rm "aws_s3_bucket_lifecycle_configuration.tableflow" >/dev/null 2>&1 || true

      echo -e "${GREEN}✓ S3 bucket and related resources removed from Terraform state${NC}"
    fi
    popd >/dev/null
  fi

  # Ensure AWS SDK uses the same region
  export AWS_DEFAULT_REGION="${AWS_REGION}"

  echo -e "${CYAN}Using AWS region: ${AWS_REGION}${NC}"

  # Apply Terraform only if needed
  source "${SCRIPT_DIR}/scripts/common/terraform.sh"
  terraform_apply_if_needed "$aws_tf_dir" "AWS S3"

  # Get outputs (whether newly created or already existing)
  if [ -z "${AWS_BUCKET_NAME:-}" ]; then
    export AWS_BUCKET_NAME=$(terraform_output_raw "$aws_tf_dir" "bucket_name")
  fi
  export AWS_BUCKET_URL=$(terraform_output_raw "$aws_tf_dir" "bucket_url")

  echo -e "${GREEN}✓ AWS S3 bucket: ${AWS_BUCKET_NAME}${NC}"
  echo -e "${GREEN}✓ Bucket URL: ${AWS_BUCKET_URL}${NC}"
}
