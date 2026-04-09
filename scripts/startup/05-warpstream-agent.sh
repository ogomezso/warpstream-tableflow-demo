#!/bin/bash
# Module: WarpStream Agent Deployment
# Step 5/6 of demo startup

deploy_warpstream_agent() {
  local rendered_file="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local values_file="${tmp_dir}/warpstream-agent-values.yaml"
  local manifest_file="${tmp_dir}/warpstream-agent-manifests.yaml"

  awk '
    BEGIN { in_manifests = 0 }
    /^---[[:space:]]*$/ && in_manifests == 0 { in_manifests = 1; next }
    {
      if (in_manifests == 0) {
        print > values
      } else {
        print > manifests
      }
    }
  ' values="$values_file" manifests="$manifest_file" "$rendered_file"

  if ! grep -q '[^[:space:]]' "$values_file"; then
    echo -e "${RED}Error: Generated Helm values file is empty: ${values_file}${NC}"
    rm -rf "$tmp_dir"
    exit 1
  fi

  # Always show bucket URL for debugging MinIO issues
  echo "Helm values file bucket URL:"
  grep "bucketURL" "$values_file" || echo "  [bucketURL not found in values file]"

  if is_debug_enabled; then
    echo "Full Helm values file:"
    cat "$values_file"
    echo "---"

    local agent_key_in_values
    agent_key_in_values="$(awk -F': *' '/^[[:space:]]*agentKey:[[:space:]]*/ {print $2; exit}' "$values_file" | sed 's/^"//; s/"$//')"
    if [ -z "$agent_key_in_values" ]; then
      debug_log "ERROR: agentKey not found in values file!"
    else
      debug_log "Agent key in values file: ${agent_key_in_values:0:10}...${agent_key_in_values: -8}"
    fi
  fi

  kubectl create namespace "$WARPSTREAM_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

  if [ -f "$manifest_file" ] && grep -q '[^[:space:]]' "$manifest_file"; then
    sed -i '' "s|namespace: default|namespace: ${WARPSTREAM_NAMESPACE}|g" "$manifest_file"
    kubectl apply -f "$manifest_file"
  fi

  helm repo add "$WARPSTREAM_HELM_REPO_NAME" "$WARPSTREAM_HELM_REPO_URL" >/dev/null 2>&1 || true
  helm repo update >/dev/null

  helm upgrade --install "$WARPSTREAM_HELM_RELEASE" "$WARPSTREAM_HELM_CHART" \
    --namespace "$WARPSTREAM_NAMESPACE" \
    --create-namespace \
    -f "$values_file"

  rm -rf "$tmp_dir"
}

run_step_warpstream_agent() {
  echo -e "${YELLOW}[5/7] Rendering and deploying WarpStream agent...${NC}"

  # Get WarpStream cluster info (common to both backends)
  if [ -n "${WARPSTREAM_AGENT_KEY_OVERRIDE:-}" ]; then
    WARPSTREAM_AGENT_KEY="${WARPSTREAM_AGENT_KEY_OVERRIDE}"
    echo -e "${YELLOW}Using WARPSTREAM_AGENT_KEY from environment override.${NC}"
  else
    WARPSTREAM_AGENT_KEY="$(terraform_output_raw "$WARPSTREAM_TF_DIR" "tableflow_agent_key")"
  fi
  WARPSTREAM_VIRTUAL_CLUSTER_ID="$(terraform_output_raw "$WARPSTREAM_TF_DIR" "tableflow_virtual_cluster_id")"

  # Configure based on selected backend
  local backend="${TABLEFLOW_BACKEND:-azure}"
  local template_file=""

  if [ "$backend" = "minio" ]; then
    echo -e "${GREEN}Configuring WarpStream agent for MinIO backend${NC}"
    template_file="${SCRIPT_DIR}/environment/warpstream/agent/warpstream-agent-minio-template.yaml"

    # Validate MinIO configuration
    if [ -z "${MINIO_BUCKET:-}" ] || [ -z "${MINIO_ACCESS_KEY:-}" ] || [ -z "${MINIO_SECRET_KEY:-}" ]; then
      echo -e "${RED}Error: MinIO configuration is incomplete.${NC}"
      echo "Required: MINIO_BUCKET, MINIO_ACCESS_KEY, MINIO_SECRET_KEY"
      exit 1
    fi
  else
    echo -e "${GREEN}Configuring WarpStream agent for Azure ADLS Gen2 backend${NC}"
    template_file="$WARPSTREAM_TEMPLATE_FILE"
    AZURE_STORAGE_ACCOUNT="$(terraform_output_raw "$AZURE_TF_DIR" "storage_account_name")"
    AZURE_STORAGE_KEY="$(terraform_output_raw "$AZURE_TF_DIR" "storage_account_primary_access_key")"
    TABLEFLOW_CONTAINER="$(terraform_output_raw "$AZURE_TF_DIR" "tableflow_container_name")"

    # Validate Azure configuration
    if [ -z "$AZURE_STORAGE_ACCOUNT" ] || [ -z "$AZURE_STORAGE_KEY" ] || [ -z "$TABLEFLOW_CONTAINER" ]; then
      echo -e "${RED}Error: Azure configuration is incomplete.${NC}"
      if is_debug_enabled; then
        echo "Debug info:"
        echo "  AZURE_STORAGE_ACCOUNT: ${AZURE_STORAGE_ACCOUNT:-[empty]}"
        echo "  AZURE_STORAGE_KEY: ${AZURE_STORAGE_KEY:+[SET $((${#AZURE_STORAGE_KEY})) chars]}${AZURE_STORAGE_KEY:-[empty]}"
        echo "  TABLEFLOW_CONTAINER: ${TABLEFLOW_CONTAINER:-[empty]}"
      fi
      exit 1
    fi
  fi

  # Validate common WarpStream configuration
  if [ -z "$WARPSTREAM_AGENT_KEY" ] || [ -z "$WARPSTREAM_VIRTUAL_CLUSTER_ID" ]; then
    echo -e "${RED}Error: WarpStream configuration is incomplete.${NC}"
    if is_debug_enabled; then
      echo "  WARPSTREAM_AGENT_KEY: ${WARPSTREAM_AGENT_KEY:-[empty]}"
      echo "  WARPSTREAM_VIRTUAL_CLUSTER_ID: ${WARPSTREAM_VIRTUAL_CLUSTER_ID:-[empty]}"
    fi
    exit 1
  fi

  if [[ ! "$WARPSTREAM_AGENT_KEY" =~ ^aks_ ]]; then
    echo -e "${RED}Error: WARPSTREAM_AGENT_KEY does not start with 'aks_' prefix.${NC}"
    echo -e "${YELLOW}Retrieved key format: ${WARPSTREAM_AGENT_KEY:0:50}...${NC}"
    echo -e "${RED}This may indicate an issue with WarpStream provider version or Terraform state.${NC}"
    echo "Troubleshooting steps:"
    echo "  1. Verify Terraform state: terraform -chdir='$WARPSTREAM_TF_DIR' state list"
    echo "  2. Check agent key resource: terraform -chdir='$WARPSTREAM_TF_DIR' state show warpstream_agent_key.demo_agent_key"
    echo "  3. Manually set with: export WARPSTREAM_AGENT_KEY='aks_<key>'"
    exit 1
  fi

  if is_debug_enabled; then
    debug_log "Agent key format: ${WARPSTREAM_AGENT_KEY:0:10}...${WARPSTREAM_AGENT_KEY: -8}"
    debug_log "Backend: ${backend}"
  fi

  # Remove old generated file to ensure clean start
  if [ -f "$WARPSTREAM_AGENT_FILE" ]; then
    BACKUP_FILE="${WARPSTREAM_AGENT_FILE}.backup.$(date +%s)"
    mv "$WARPSTREAM_AGENT_FILE" "$BACKUP_FILE"
    echo "Backed up old agent config to: $BACKUP_FILE"
  fi

  cp "$template_file" "$WARPSTREAM_AGENT_FILE"

  # Replace common placeholders
  sed -i '' "s|<TABLEFLOW_VIRTUAL_CLUSTER_ID>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g" "$WARPSTREAM_AGENT_FILE"
  sed -i '' "s|<TABLEFLOW_REGION>|${TABLEFLOW_REGION}|g" "$WARPSTREAM_AGENT_FILE"
  sed -i '' "s|<WARPSTREAM_AGENT_KEY>|${WARPSTREAM_AGENT_KEY}|g" "$WARPSTREAM_AGENT_FILE"

  # Replace backend-specific placeholders
  if [ "$backend" = "minio" ]; then
    sed -i '' "s|<MINIO_BUCKET>|${MINIO_BUCKET}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<MINIO_ACCESS_KEY>|${MINIO_ACCESS_KEY}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<MINIO_SECRET_KEY>|${MINIO_SECRET_KEY}|g" "$WARPSTREAM_AGENT_FILE"
  else
    sed -i '' "s|<TABLEFLOW_CONTAINER>|${TABLEFLOW_CONTAINER}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<AZURE_STORAGE_ACCOUNT>|${AZURE_STORAGE_ACCOUNT}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<AZURE_STORAGE_KEY>|${AZURE_STORAGE_KEY}|g" "$WARPSTREAM_AGENT_FILE"
  fi

  # Note: No need to replace bucketURL line - the template already has the correct format
  # and the placeholders have been replaced above

  deploy_warpstream_agent "$WARPSTREAM_AGENT_FILE"

  echo -e "${GREEN}✓ WarpStream agent deployed with ${backend} backend${NC}"
  if [ -f "${BACKUP_FILE:-}" ]; then
    echo -e "${GREEN}✓ Backup created: ${BACKUP_FILE}${NC}"
  fi
  echo
}
