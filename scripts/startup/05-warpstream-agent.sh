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

  # Apply additional manifests (e.g., secrets, configmaps)
  if [ -f "$manifest_file" ] && grep -q '[^[:space:]]' "$manifest_file"; then
    sed -i '' "s|namespace: default|namespace: ${WARPSTREAM_NAMESPACE}|g" "$manifest_file"
    kubectl apply -f "$manifest_file"
  fi

  helm repo add "$WARPSTREAM_HELM_REPO_NAME" "$WARPSTREAM_HELM_REPO_URL" >/dev/null 2>&1 || true
  helm repo update >/dev/null 2>&1 || echo -e "${YELLOW}Warning: Could not update Helm repos (continuing with cached version)${NC}"

  helm upgrade --install "$WARPSTREAM_HELM_RELEASE" "$WARPSTREAM_HELM_CHART" \
    --namespace "$WARPSTREAM_NAMESPACE" \
    --create-namespace \
    -f "$values_file"

  rm -rf "$tmp_dir"
}

# Function to patch WarpStream deployment to add volume mounts (for backends that need file-based credentials)
patch_warpstream_deployment_volumes() {
  local namespace="$1"
  local volume_name="$2"
  local secret_name="$3"
  local mount_path="$4"

  echo -e "${CYAN}Patching deployment to add ${volume_name} volume mount...${NC}"

  # Get current deployment and add volume + volumeMount
  kubectl get deployment warpstream-agent -n "$namespace" -o json | \
    jq --arg vol_name "$volume_name" \
       --arg secret_name "$secret_name" \
       --arg mount_path "$mount_path" \
       '.spec.template.spec.volumes += [{"name": $vol_name, "secret": {"secretName": $secret_name}}] |
        .spec.template.spec.containers[0].volumeMounts += [{"name": $vol_name, "mountPath": $mount_path, "readOnly": true}]' | \
    kubectl apply -f -

  # Wait for rollout
  echo -e "${CYAN}Waiting for deployment rollout...${NC}"
  kubectl rollout status deployment/warpstream-agent -n "$namespace" --timeout=120s
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

  # Get WarpStream control plane region from Terraform cloud configuration
  WARPSTREAM_CONTROL_PLANE_REGION="$(cd "$WARPSTREAM_TF_DIR" && terraform show -json 2>/dev/null | jq -r '.values.root_module.resources[] | select(.type == "warpstream_tableflow_cluster") | .values.cloud.region' || echo "us-east-1")"

  if is_debug_enabled; then
    debug_log "WarpStream control plane region: ${WARPSTREAM_CONTROL_PLANE_REGION}"
  fi

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
  elif [ "$backend" = "cloud" ]; then
    # Cloud backend - check which cloud provider
    case "${CLOUD_PROVIDER:-}" in
      aws)
        echo -e "${GREEN}Configuring WarpStream agent for AWS S3 backend${NC}"
        template_file="${SCRIPT_DIR}/environment/warpstream/agent/warpstream-agent-aws-template.yaml"

        # Get AWS credentials from environment (set by validate_aws_credentials)
        AWS_BUCKET_NAME="${AWS_BUCKET_NAME:-}"
        AWS_BUCKET_URL="${AWS_BUCKET_URL:-}"

        # If not set, try to get from Terraform output
        if [ -z "$AWS_BUCKET_NAME" ]; then
          local aws_tf_dir="${SCRIPT_DIR}/environment/aws"
          AWS_BUCKET_NAME="$(terraform_output_raw "$aws_tf_dir" "bucket_name" 2>/dev/null || echo "")"
          AWS_BUCKET_URL="$(terraform_output_raw "$aws_tf_dir" "bucket_url" 2>/dev/null || echo "")"
        fi

        # Validate AWS configuration
        if [ -z "$AWS_BUCKET_NAME" ] || [ -z "$AWS_BUCKET_URL" ] || [ -z "${AWS_REGION:-}" ]; then
          echo -e "${RED}Error: AWS configuration is incomplete.${NC}"
          echo "Required: AWS_BUCKET_NAME, AWS_BUCKET_URL, AWS_REGION"
          if is_debug_enabled; then
            echo "Debug info:"
            echo "  AWS_BUCKET_NAME: ${AWS_BUCKET_NAME:-[empty]}"
            echo "  AWS_BUCKET_URL: ${AWS_BUCKET_URL:-[empty]}"
            echo "  AWS_REGION: ${AWS_REGION:-[empty]}"
          fi
          exit 1
        fi
        ;;
      gcp)
        echo -e "${GREEN}Configuring WarpStream agent for GCP GCS backend${NC}"
        template_file="${SCRIPT_DIR}/environment/warpstream/agent/warpstream-agent-gcp-template.yaml"

        # Get GCP configuration
        GCP_BUCKET_NAME="${GCP_BUCKET_NAME:-}"
        GCP_BUCKET_URL="${GCP_BUCKET_URL:-}"

        # If not set, try to get from Terraform output
        if [ -z "$GCP_BUCKET_NAME" ]; then
          local gcp_tf_dir="${SCRIPT_DIR}/environment/gcp"
          GCP_BUCKET_NAME="$(terraform_output_raw "$gcp_tf_dir" "bucket_name" 2>/dev/null || echo "")"
          GCP_BUCKET_URL="$(terraform_output_raw "$gcp_tf_dir" "bucket_url" 2>/dev/null || echo "")"
        fi

        # Validate GCP configuration
        if [ -z "$GCP_BUCKET_NAME" ] || [ -z "$GCP_BUCKET_URL" ]; then
          echo -e "${RED}Error: GCP configuration is incomplete.${NC}"
          echo "Required: GCP_BUCKET_NAME, GCP_BUCKET_URL"
          exit 1
        fi
        ;;
      azure)
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
        ;;
      *)
        echo -e "${RED}Error: Unknown cloud provider: ${CLOUD_PROVIDER:-[not set]}${NC}"
        exit 1
        ;;
    esac
  else
    # Legacy: default to Azure if backend is not explicitly set
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

  # Replace backend-specific placeholders
  if [ "$backend" = "minio" ]; then
    # Common placeholders
    sed -i '' "s|<TABLEFLOW_VIRTUAL_CLUSTER_ID>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<WARPSTREAM_CONTROL_PLANE_REGION>|${WARPSTREAM_CONTROL_PLANE_REGION}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<WARPSTREAM_AGENT_KEY>|${WARPSTREAM_AGENT_KEY}|g" "$WARPSTREAM_AGENT_FILE"
    # MinIO-specific placeholders
    sed -i '' "s|<MINIO_BUCKET>|${MINIO_BUCKET}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<MINIO_ACCESS_KEY>|${MINIO_ACCESS_KEY}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<MINIO_SECRET_KEY>|${MINIO_SECRET_KEY}|g" "$WARPSTREAM_AGENT_FILE"
  elif [ "$backend" = "cloud" ]; then
    case "${CLOUD_PROVIDER:-}" in
      aws)
        # Get AWS credentials from the environment (assumes AWS CLI session is active)
        local aws_access_key="${AWS_ACCESS_KEY_ID:-}"
        local aws_secret_key="${AWS_SECRET_ACCESS_KEY:-}"
        local aws_session_token="${AWS_SESSION_TOKEN:-}"

        # For AWS SSO/granted assume, credentials are in env vars
        sed -i '' "s|<AWS_ACCESS_KEY_ID>|${aws_access_key}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<AWS_SECRET_ACCESS_KEY>|${aws_secret_key}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<AWS_SESSION_TOKEN>|${aws_session_token}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<AGENT_KEY>|${WARPSTREAM_AGENT_KEY}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<VIRTUAL_CLUSTER_ID>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<BUCKET_URL>|${AWS_BUCKET_URL}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<AWS_REGION>|${AWS_REGION}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<WARPSTREAM_CONTROL_PLANE_REGION>|${WARPSTREAM_CONTROL_PLANE_REGION}|g" "$WARPSTREAM_AGENT_FILE"
        ;;
      gcp)
        sed -i '' "s|<AGENT_KEY>|${WARPSTREAM_AGENT_KEY}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<VIRTUAL_CLUSTER_ID>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<BUCKET_URL>|${GCP_BUCKET_URL}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<GCP_PROJECT>|${GCP_PROJECT}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<GCP_REGION>|${GCP_REGION}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<WARPSTREAM_CONTROL_PLANE_REGION>|${WARPSTREAM_CONTROL_PLANE_REGION}|g" "$WARPSTREAM_AGENT_FILE"

        # Create GCP credentials secret (matches pattern from environment/trino/deploy-gcp.sh)
        # Ensure namespace exists before creating secret
        echo -e "${CYAN}Ensuring namespace ${WARPSTREAM_NAMESPACE} exists...${NC}"
        kubectl create namespace "$WARPSTREAM_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f - || {
          echo -e "${YELLOW}Note: Namespace may already exist${NC}"
        }

        # Wait a moment for namespace to be ready
        kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/"$WARPSTREAM_NAMESPACE" --timeout=30s || true

        echo -e "${CYAN}Creating GCP credentials secret in ${WARPSTREAM_NAMESPACE} namespace...${NC}"

        if [ -n "${GOOGLE_APPLICATION_CREDENTIALS:-}" ] && [ -f "${GOOGLE_APPLICATION_CREDENTIALS}" ]; then
          kubectl create secret generic gcp-storage-credentials \
            --from-file=credentials.json="${GOOGLE_APPLICATION_CREDENTIALS}" \
            --namespace="${WARPSTREAM_NAMESPACE}" \
            --dry-run=client -o yaml | kubectl apply -f -
        else
          echo -e "${YELLOW}Warning: GOOGLE_APPLICATION_CREDENTIALS not set. Using gcloud application-default credentials...${NC}"
          gcloud_creds="${HOME}/.config/gcloud/application_default_credentials.json"
          if [ -f "$gcloud_creds" ]; then
            kubectl create secret generic gcp-storage-credentials \
              --from-file=credentials.json="$gcloud_creds" \
              --namespace="${WARPSTREAM_NAMESPACE}" \
              --dry-run=client -o yaml | kubectl apply -f -
          else
            echo -e "${RED}Error: No GCP credentials found.${NC}"
            echo "Please run: gcloud auth application-default login"
            exit 1
          fi
        fi
        ;;
      azure)
        # Common placeholders
        sed -i '' "s|<TABLEFLOW_VIRTUAL_CLUSTER_ID>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<WARPSTREAM_CONTROL_PLANE_REGION>|${WARPSTREAM_CONTROL_PLANE_REGION}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<WARPSTREAM_AGENT_KEY>|${WARPSTREAM_AGENT_KEY}|g" "$WARPSTREAM_AGENT_FILE"
        # Azure-specific placeholders
        sed -i '' "s|<TABLEFLOW_CONTAINER>|${TABLEFLOW_CONTAINER}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<AZURE_STORAGE_ACCOUNT>|${AZURE_STORAGE_ACCOUNT}|g" "$WARPSTREAM_AGENT_FILE"
        sed -i '' "s|<AZURE_STORAGE_KEY>|${AZURE_STORAGE_KEY}|g" "$WARPSTREAM_AGENT_FILE"
        ;;
    esac
  else
    # Legacy: Azure
    # Common placeholders
    sed -i '' "s|<TABLEFLOW_VIRTUAL_CLUSTER_ID>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<WARPSTREAM_CONTROL_PLANE_REGION>|${WARPSTREAM_CONTROL_PLANE_REGION}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<WARPSTREAM_AGENT_KEY>|${WARPSTREAM_AGENT_KEY}|g" "$WARPSTREAM_AGENT_FILE"
    # Azure-specific placeholders
    sed -i '' "s|<TABLEFLOW_CONTAINER>|${TABLEFLOW_CONTAINER}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<AZURE_STORAGE_ACCOUNT>|${AZURE_STORAGE_ACCOUNT}|g" "$WARPSTREAM_AGENT_FILE"
    sed -i '' "s|<AZURE_STORAGE_KEY>|${AZURE_STORAGE_KEY}|g" "$WARPSTREAM_AGENT_FILE"
  fi

  # Note: No need to replace bucketURL line - the template already has the correct format
  # and the placeholders have been replaced above

  deploy_warpstream_agent "$WARPSTREAM_AGENT_FILE"

  # For GCP, patch the deployment to add credentials volume mount
  # (WarpStream Helm chart doesn't support extraVolumes/extraVolumeMounts)
  if [ "$backend" = "cloud" ] && [ "${CLOUD_PROVIDER:-}" = "gcp" ]; then
    patch_warpstream_deployment_volumes \
      "$WARPSTREAM_NAMESPACE" \
      "gcp-credentials" \
      "gcp-storage-credentials" \
      "/var/secrets/google"
  fi

  echo -e "${GREEN}✓ WarpStream agent deployed with ${backend} backend${NC}"
  if [ -f "${BACKUP_FILE:-}" ]; then
    echo -e "${GREEN}✓ Backup created: ${BACKUP_FILE}${NC}"
  fi
  echo
}
