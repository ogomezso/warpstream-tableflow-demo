#!/bin/bash

################################################################################
# Script: 03d-aws.sh
# Description: Cleanup AWS S3 backend resources
################################################################################

run_cleanup_aws() {
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Cleanup: AWS S3 Backend${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local aws_tf_dir="${SCRIPT_DIR}/environment/aws"

  # Check if AWS Terraform state exists
  if [ ! -f "${aws_tf_dir}/terraform.tfstate" ]; then
    echo -e "${CYAN}No AWS Terraform state found - skipping AWS cleanup${NC}"
    return 0
  fi

  # Check if bucket is managed by Terraform by looking at state
  local bucket_region=""
  if [ -f "${aws_tf_dir}/terraform.tfstate" ]; then
    pushd "${aws_tf_dir}" >/dev/null
    terraform init -input=false >/dev/null 2>&1 || true

    local bucket_in_state=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[]? | select(.type == "aws_s3_bucket" and .name == "tableflow") | .address' || echo "")
    if [ -z "$bucket_in_state" ]; then
      echo -e "${YELLOW}S3 bucket not managed by Terraform${NC}"
      export AWS_CREATE_BUCKET="false"
    else
      export AWS_CREATE_BUCKET="true"
      bucket_region=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type == "aws_s3_bucket") | .values.region' 2>/dev/null || echo "")
      if [ -n "$bucket_region" ]; then
        echo -e "${CYAN}Detected bucket region from state: ${bucket_region}${NC}"
        export AWS_REGION="$bucket_region"
        export AWS_DEFAULT_REGION="$bucket_region"
        export TABLEFLOW_REGION="$bucket_region"
      fi
    fi

    popd >/dev/null
  fi

  # Source AWS helper functions
  source "${SCRIPT_DIR}/scripts/common/aws.sh"

  # Validate AWS credentials (only if state exists)
  echo -e "${CYAN}Validating AWS credentials...${NC}"
  validate_aws_credentials

  # Empty the S3 bucket before destroying (required for versioned buckets)
  local bucket_name=$(cd "$aws_tf_dir" && terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type == "aws_s3_bucket") | .values.bucket' 2>/dev/null || echo "")
  if [ -n "$bucket_name" ] && [ -n "$bucket_region" ]; then
    echo -e "${CYAN}Emptying S3 bucket: ${bucket_name}...${NC}"
    local empty_script="${SCRIPT_DIR}/scripts/cleanup/helpers/empty-s3-bucket.sh"
    if [ -f "$empty_script" ]; then
      bash "$empty_script" "$bucket_name" "$bucket_region" || echo -e "${YELLOW}Warning: Failed to empty bucket, will try Terraform destroy anyway${NC}"
    else
      echo -e "${YELLOW}Warning: empty-s3-bucket.sh not found, attempting Terraform destroy anyway${NC}"
    fi
  fi

  # Destroy AWS resources
  echo -e "${CYAN}Destroying AWS S3 bucket via Terraform...${NC}"

  cd "$aws_tf_dir" || exit 1

  # Set Terraform variables - use the bucket's actual region
  if [ -f "terraform.tfstate" ]; then
    # Get bucket name from state for Terraform
    local tf_bucket_name=$(terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type == "aws_s3_bucket") | .values.bucket' 2>/dev/null || echo "")
    if [ -n "$tf_bucket_name" ]; then
      export TF_VAR_bucket_name="$tf_bucket_name"
    fi

    # Ensure we're using the bucket's region, not the current AWS_REGION
    if [ -n "$bucket_region" ]; then
      export TF_VAR_region="$bucket_region"
      export AWS_REGION="$bucket_region"
      export AWS_DEFAULT_REGION="$bucket_region"
    else
      export TF_VAR_region="${AWS_REGION:-us-east-1}"
    fi

    terraform init -upgrade
    terraform destroy -auto-approve

    # Clean up Terraform files
    rm -rf .terraform
    rm -f .terraform.lock.hcl
    rm -f terraform.tfstate*
    rm -f tfplan
  fi

  cd - > /dev/null

  echo -e "${GREEN}✓ AWS resources cleaned up${NC}"
}
