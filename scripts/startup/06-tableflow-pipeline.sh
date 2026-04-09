#!/bin/bash
# Module: Tableflow Pipeline Creation
# Step 6/7 of demo startup

run_step_tableflow_pipeline() {
  echo -e "${YELLOW}[6/7] Creating Tableflow pipeline for orders topic...${NC}"

  # Construct bucket URL based on backend
  local backend="${TABLEFLOW_BACKEND:-azure}"
  local bucket_url=""

  if [ "$backend" = "minio" ]; then
    bucket_url="s3://${MINIO_BUCKET}?region=us-east-1&s3ForcePathStyle=true&endpoint=http://minio.minio.svc.cluster.local:9000"
  else
    # Azure backend
    TABLEFLOW_CONTAINER="$(terraform_output_raw "$AZURE_TF_DIR" "tableflow_container_name")"
    bucket_url="azblob://${TABLEFLOW_CONTAINER}"
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
