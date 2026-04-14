#!/bin/bash
# Module: Tableflow Pipeline Creation
# Step 6/7 of demo startup

run_step_tableflow_pipeline() {
  echo -e "${YELLOW}[6/7] Creating Tableflow pipeline for orders topic...${NC}"

  # Construct bucket URL based on backend
  local backend="${TABLEFLOW_BACKEND:-azure}"
  local bucket_url=""

  echo -e "${CYAN}Determining bucket URL for backend: ${backend} (cloud provider: ${CLOUD_PROVIDER:-none})${NC}"

  if [ "$backend" = "minio" ]; then
    bucket_url="s3://${MINIO_BUCKET}?region=us-east-1&s3ForcePathStyle=true&endpoint=http://minio.minio.svc.cluster.local:9000"
  elif [ "$backend" = "cloud" ]; then
    # Cloud backend - check which cloud provider
    case "${CLOUD_PROVIDER:-}" in
      aws)
        local aws_tf_dir="${SCRIPT_DIR}/environment/aws"
        local aws_bucket=$(terraform_output_raw "$aws_tf_dir" "bucket_name" 2>/dev/null || echo "${AWS_BUCKET_NAME:-}")

        if [ -z "$aws_bucket" ]; then
          echo -e "${RED}Error: Could not determine AWS bucket name${NC}"
          echo -e "${YELLOW}AWS_BUCKET_NAME env var: ${AWS_BUCKET_NAME:-[not set]}${NC}"
          echo -e "${YELLOW}Terraform output attempt failed${NC}"
          exit 1
        fi

        # WarpStream requires region parameter for S3 buckets
        local aws_region="${AWS_REGION:-${TABLEFLOW_REGION:-us-east-1}}"
        bucket_url="s3://${aws_bucket}?region=${aws_region}"
        echo -e "${GREEN}✓ Using AWS S3 bucket: ${aws_bucket} (region: ${aws_region})${NC}"
        ;;
      gcp)
        local gcp_tf_dir="${SCRIPT_DIR}/environment/gcp"
        local gcp_bucket=$(terraform_output_raw "$gcp_tf_dir" "bucket_name" 2>/dev/null || echo "${GCP_BUCKET_NAME:-}")

        if [ -z "$gcp_bucket" ]; then
          echo -e "${RED}Error: Could not determine GCP bucket name${NC}"
          echo -e "${YELLOW}GCP_BUCKET_NAME env var: ${GCP_BUCKET_NAME:-[not set]}${NC}"
          echo -e "${YELLOW}Terraform output attempt failed${NC}"
          exit 1
        fi

        bucket_url="gs://${gcp_bucket}"
        echo -e "${GREEN}✓ Using GCP GCS bucket: ${gcp_bucket}${NC}"
        ;;
      azure)
        TABLEFLOW_CONTAINER="$(terraform_output_raw "$AZURE_TF_DIR" "tableflow_container_name" 2>/dev/null)"
        local azure_storage_account="$(terraform_output_raw "$AZURE_TF_DIR" "storage_account_name" 2>/dev/null)"

        if [ -z "$TABLEFLOW_CONTAINER" ]; then
          echo -e "${RED}Error: Could not determine Azure container name${NC}"
          exit 1
        fi

        if [ -z "$azure_storage_account" ]; then
          echo -e "${RED}Error: Could not determine Azure storage account name${NC}"
          exit 1
        fi

        bucket_url="azblob://${TABLEFLOW_CONTAINER}?storage_account=${azure_storage_account}"
        echo -e "${GREEN}✓ Using Azure container: ${TABLEFLOW_CONTAINER} (storage account: ${azure_storage_account})${NC}"
        ;;
      *)
        echo -e "${RED}Error: Unknown cloud provider: ${CLOUD_PROVIDER:-[not set]}${NC}"
        exit 1
        ;;
    esac
  else
    # Legacy: Azure backend
    TABLEFLOW_CONTAINER="$(terraform_output_raw "$AZURE_TF_DIR" "tableflow_container_name" 2>/dev/null)"
    local azure_storage_account="$(terraform_output_raw "$AZURE_TF_DIR" "storage_account_name" 2>/dev/null)"

    if [ -z "$TABLEFLOW_CONTAINER" ]; then
      echo -e "${RED}Error: Could not determine Azure container name${NC}"
      exit 1
    fi

    if [ -z "$azure_storage_account" ]; then
      echo -e "${RED}Error: Could not determine Azure storage account name${NC}"
      exit 1
    fi

    bucket_url="azblob://${TABLEFLOW_CONTAINER}?storage_account=${azure_storage_account}"
    echo -e "${GREEN}✓ Using Azure container: ${TABLEFLOW_CONTAINER} (storage account: ${azure_storage_account})${NC}"
  fi

  CP_BROKER_DNS="kafka.confluent.svc.cluster.local"
  cp "$TABLEFLOW_PIPELINE_TEMPLATE" "$TABLEFLOW_PIPELINE_FILE"
  sed -i '' "s|<CP_BROKER_DNS>|${CP_BROKER_DNS}|g" "$TABLEFLOW_PIPELINE_FILE"

  # Replace bucket URL using a simple line-by-line approach to avoid escaping issues
  # This method doesn't use regex replacement, so special characters like & are safe
  local temp_file="${TABLEFLOW_PIPELINE_FILE}.tmp"
  while IFS= read -r line; do
    if [[ "$line" == *"<BUCKET_URL>"* ]]; then
      echo "${line//<BUCKET_URL>/$bucket_url}"
    else
      echo "$line"
    fi
  done < "$TABLEFLOW_PIPELINE_FILE" > "$temp_file"
  mv "$temp_file" "$TABLEFLOW_PIPELINE_FILE"

  # Verify the replacement worked correctly
  if grep -q "<BUCKET_URL>" "$TABLEFLOW_PIPELINE_FILE"; then
    echo -e "${RED}ERROR: Bucket URL placeholder was not replaced!${NC}"
    cat "$TABLEFLOW_PIPELINE_FILE"
    exit 1
  fi

  # Verify the bucket URL is valid (not empty, not containing error messages)
  if [ -z "$bucket_url" ] || [[ "$bucket_url" == *"Warning"* ]] || [[ "$bucket_url" == *"Error"* ]]; then
    echo -e "${RED}ERROR: Invalid bucket URL generated: ${bucket_url}${NC}"
    echo -e "${RED}This usually means the cloud backend wasn't properly configured${NC}"
    exit 1
  fi

  echo "Generated pipeline with bucket URL: ${bucket_url}"
  echo -e "${GREEN}✓ Generated: ${TABLEFLOW_PIPELINE_FILE}${NC}"

  # Show the actual bucket URL in the pipeline for debugging
  echo "Actual bucket URL in pipeline:"
  grep "destination_bucket_url" "$TABLEFLOW_PIPELINE_FILE" || true

  pushd "$TABLEFLOW_PIPELINE_TF_DIR" >/dev/null
  terraform init -input=false >/dev/null

  TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" \
  TF_VAR_tableflow_virtual_cluster_id="$WARPSTREAM_VIRTUAL_CLUSTER_ID" \
  terraform apply -auto-approve

  popd >/dev/null
  echo -e "${GREEN}✓ Tableflow pipeline created${NC}"
}
