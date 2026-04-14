#!/bin/bash
# Terraform helper functions

terraform_apply_if_needed() {
  local tf_dir="$1"
  local label="$2"
  local plan_file=".demo-startup.tfplan"
  local aws_tf_dir="${SCRIPT_DIR}/environment/aws"
  local gcp_tf_dir="${SCRIPT_DIR}/environment/gcp"

  pushd "$tf_dir" >/dev/null
  terraform init -input=false >/dev/null

  set +e
  if [ "$tf_dir" = "$WARPSTREAM_TF_DIR" ]; then
    # Determine cloud provider and region for WarpStream cluster
    local warpstream_cloud_provider
    local warpstream_cloud_region

    # For MinIO backend, use the user's selected cloud provider
    # (MinIO stores data locally, but WarpStream cluster is in the cloud)
    if [ "${TABLEFLOW_BACKEND:-}" = "minio" ]; then
      warpstream_cloud_provider="${CLOUD_PROVIDER:-azure}"

      if [ "$warpstream_cloud_provider" = "aws" ]; then
        warpstream_cloud_region="${AWS_REGION:-${TABLEFLOW_REGION:-us-east-1}}"
      elif [ "$warpstream_cloud_provider" = "gcp" ]; then
        warpstream_cloud_region="${GCP_REGION:-${TABLEFLOW_REGION:-us-central1}}"
      else
        warpstream_cloud_region="${TABLEFLOW_REGION:-eastus}"
      fi
    else
      # For cloud backends, use the actual cloud provider
      warpstream_cloud_provider="${CLOUD_PROVIDER:-azure}"

      if [ "$warpstream_cloud_provider" = "aws" ]; then
        warpstream_cloud_region="${AWS_REGION:-us-east-1}"
      elif [ "$warpstream_cloud_provider" = "gcp" ]; then
        warpstream_cloud_region="${GCP_REGION:-us-central1}"
      else
        warpstream_cloud_region="${TABLEFLOW_REGION:-eastus}"
      fi
    fi

    TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" \
    TF_VAR_cloud_provider="$warpstream_cloud_provider" \
    TF_VAR_cloud_region="$warpstream_cloud_region" \
    terraform plan -input=false -detailed-exitcode -out="$plan_file" >/dev/null
  elif [ "$tf_dir" = "$AZURE_TF_DIR" ]; then
    TF_VAR_location="${TABLEFLOW_REGION}" \
    TF_VAR_resource_group_name="${AZURE_RESOURCE_GROUP:-warpstream-tableflow-demo}" \
    TF_VAR_create_resource_group="${AZURE_CREATE_RESOURCE_GROUP:-true}" \
    TF_VAR_owner_email="${AZURE_OWNER_EMAIL:-}" \
    TF_VAR_storage_account_name="${AZURE_STORAGE_ACCOUNT:-wstableflowdemo}" \
    TF_VAR_create_storage_account="${AZURE_CREATE_STORAGE_ACCOUNT:-true}" \
    TF_VAR_container_name="${AZURE_CONTAINER:-tableflow}" \
    TF_VAR_create_container="${AZURE_CREATE_CONTAINER:-true}" \
    terraform plan -input=false -detailed-exitcode -out="$plan_file" >/dev/null
  elif [ "$tf_dir" = "$aws_tf_dir" ]; then
    TF_VAR_region="${AWS_REGION}" \
    TF_VAR_bucket_name="${AWS_BUCKET_NAME:-}" \
    TF_VAR_create_bucket="${AWS_CREATE_BUCKET:-true}" \
    terraform plan -input=false -detailed-exitcode -out="$plan_file" >/dev/null
  elif [ "$tf_dir" = "$gcp_tf_dir" ]; then
    TF_VAR_project_id="${GCP_PROJECT}" \
    TF_VAR_region="${GCP_REGION}" \
    TF_VAR_bucket_name="${GCP_BUCKET_NAME:-}" \
    TF_VAR_create_bucket="${GCP_CREATE_BUCKET:-true}" \
    terraform plan -input=false -detailed-exitcode -out="$plan_file" >/dev/null
  else
    terraform plan -input=false -detailed-exitcode -out="$plan_file" >/dev/null
  fi
  local plan_rc=$?
  set -e

  if [ "$plan_rc" -eq 0 ]; then
    echo -e "${GREEN}✓ ${label}: no terraform changes needed${NC}"
    rm -f "$plan_file"
    popd >/dev/null
    return
  fi

  if [ "$plan_rc" -ne 2 ]; then
    echo -e "${RED}Error: terraform plan failed for ${label}.${NC}"
    rm -f "$plan_file"
    popd >/dev/null
    exit 1
  fi

  echo -e "${YELLOW}${label}: changes detected, applying...${NC}"
  if [ "$tf_dir" = "$WARPSTREAM_TF_DIR" ]; then
    # Determine cloud provider and region for WarpStream cluster
    local warpstream_cloud_provider
    local warpstream_cloud_region

    # For MinIO backend, use the user's selected cloud provider
    # (MinIO stores data locally, but WarpStream cluster is in the cloud)
    if [ "${TABLEFLOW_BACKEND:-}" = "minio" ]; then
      warpstream_cloud_provider="${CLOUD_PROVIDER:-azure}"

      if [ "$warpstream_cloud_provider" = "aws" ]; then
        warpstream_cloud_region="${AWS_REGION:-${TABLEFLOW_REGION:-us-east-1}}"
      elif [ "$warpstream_cloud_provider" = "gcp" ]; then
        warpstream_cloud_region="${GCP_REGION:-${TABLEFLOW_REGION:-us-central1}}"
      else
        warpstream_cloud_region="${TABLEFLOW_REGION:-eastus}"
      fi
    else
      # For cloud backends, use the actual cloud provider
      warpstream_cloud_provider="${CLOUD_PROVIDER:-azure}"

      if [ "$warpstream_cloud_provider" = "aws" ]; then
        warpstream_cloud_region="${AWS_REGION:-us-east-1}"
      elif [ "$warpstream_cloud_provider" = "gcp" ]; then
        warpstream_cloud_region="${GCP_REGION:-us-central1}"
      else
        warpstream_cloud_region="${TABLEFLOW_REGION:-eastus}"
      fi
    fi

    TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" \
    TF_VAR_cloud_provider="$warpstream_cloud_provider" \
    TF_VAR_cloud_region="$warpstream_cloud_region" \
    terraform apply -auto-approve "$plan_file"
  elif [ "$tf_dir" = "$AZURE_TF_DIR" ]; then
    TF_VAR_location="${TABLEFLOW_REGION}" \
    TF_VAR_resource_group_name="${AZURE_RESOURCE_GROUP:-warpstream-tableflow-demo}" \
    TF_VAR_create_resource_group="${AZURE_CREATE_RESOURCE_GROUP:-true}" \
    TF_VAR_owner_email="${AZURE_OWNER_EMAIL:-}" \
    TF_VAR_storage_account_name="${AZURE_STORAGE_ACCOUNT:-wstableflowdemo}" \
    TF_VAR_create_storage_account="${AZURE_CREATE_STORAGE_ACCOUNT:-true}" \
    TF_VAR_container_name="${AZURE_CONTAINER:-tableflow}" \
    TF_VAR_create_container="${AZURE_CREATE_CONTAINER:-true}" \
    terraform apply -auto-approve "$plan_file"
  elif [ "$tf_dir" = "$aws_tf_dir" ]; then
    TF_VAR_region="${AWS_REGION}" \
    TF_VAR_bucket_name="${AWS_BUCKET_NAME:-}" \
    TF_VAR_create_bucket="${AWS_CREATE_BUCKET:-true}" \
    terraform apply -auto-approve "$plan_file"
  elif [ "$tf_dir" = "$gcp_tf_dir" ]; then
    TF_VAR_project_id="${GCP_PROJECT}" \
    TF_VAR_region="${GCP_REGION}" \
    TF_VAR_bucket_name="${GCP_BUCKET_NAME:-}" \
    TF_VAR_create_bucket="${GCP_CREATE_BUCKET:-true}" \
    terraform apply -auto-approve "$plan_file"
  else
    terraform apply -auto-approve "$plan_file"
  fi

  rm -f "$plan_file"
  popd >/dev/null
  echo -e "${GREEN}✓ ${label}: terraform apply completed${NC}"
}

terraform_output_raw() {
  local tf_dir="$1"
  local output_name="$2"

  pushd "$tf_dir" >/dev/null
  local value
  value="$(terraform output -raw "$output_name")"
  popd >/dev/null
  echo "$value"
}

terraform_destroy_if_exists() {
  local tf_dir="$1"
  local label="$2"
  local aws_tf_dir="${SCRIPT_DIR}/environment/aws"
  local gcp_tf_dir="${SCRIPT_DIR}/environment/gcp"

  if [ ! -d "$tf_dir" ]; then
    echo -e "${YELLOW}Skipping ${label}: directory not found (${tf_dir})${NC}"
    return
  fi

  pushd "$tf_dir" >/dev/null
  if ! terraform init -input=false >/dev/null; then
    popd >/dev/null
    record_failure "${label}: terraform init failed"
    return 1
  fi

  local destroy_rc=0
  set +e
  if [ "$tf_dir" = "$WARPSTREAM_TF_DIR" ]; then
    # Determine cloud provider and region for WarpStream cluster
    local warpstream_cloud_provider
    local warpstream_cloud_region

    # For MinIO backend, use the user's selected cloud provider
    # (MinIO stores data locally, but WarpStream cluster is in the cloud)
    if [ "${TABLEFLOW_BACKEND:-}" = "minio" ]; then
      warpstream_cloud_provider="${CLOUD_PROVIDER:-azure}"

      if [ "$warpstream_cloud_provider" = "aws" ]; then
        warpstream_cloud_region="${AWS_REGION:-${TABLEFLOW_REGION:-us-east-1}}"
      elif [ "$warpstream_cloud_provider" = "gcp" ]; then
        warpstream_cloud_region="${GCP_REGION:-${TABLEFLOW_REGION:-us-central1}}"
      else
        warpstream_cloud_region="${TABLEFLOW_REGION:-eastus}"
      fi
    else
      # For cloud backends, use the actual cloud provider
      warpstream_cloud_provider="${CLOUD_PROVIDER:-azure}"

      if [ "$warpstream_cloud_provider" = "aws" ]; then
        warpstream_cloud_region="${AWS_REGION:-us-east-1}"
      elif [ "$warpstream_cloud_provider" = "gcp" ]; then
        warpstream_cloud_region="${GCP_REGION:-us-central1}"
      else
        warpstream_cloud_region="${TABLEFLOW_REGION:-eastus}"
      fi
    fi

    TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" \
    TF_VAR_cloud_provider="$warpstream_cloud_provider" \
    TF_VAR_cloud_region="$warpstream_cloud_region" \
    terraform destroy -auto-approve
  elif [ "$tf_dir" = "$TABLEFLOW_PIPELINE_TF_DIR" ]; then
    local vc_id=""
    if [ -d "$WARPSTREAM_TF_DIR" ]; then
      vc_id="$(cd "$WARPSTREAM_TF_DIR" && terraform output -raw tableflow_virtual_cluster_id 2>/dev/null || true)"
    fi
    TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" \
    TF_VAR_tableflow_virtual_cluster_id="$vc_id" \
    terraform destroy -auto-approve
  elif [ "$tf_dir" = "$aws_tf_dir" ]; then
    # For AWS: only destroy bucket if we created it (not existing ones)
    if [ "${AWS_CREATE_BUCKET:-true}" = "true" ]; then
      echo -e "${YELLOW}Destroying created AWS S3 bucket${NC}"
      TF_VAR_region="${AWS_REGION}" \
      TF_VAR_bucket_name="${AWS_BUCKET_NAME:-}" \
      TF_VAR_create_bucket="true" \
      terraform destroy -auto-approve
    else
      echo -e "${YELLOW}AWS S3 bucket is existing - nothing to destroy${NC}"
    fi
  elif [ "$tf_dir" = "$gcp_tf_dir" ]; then
    # For GCP: only destroy bucket if we created it (not existing ones)
    if [ "${GCP_CREATE_BUCKET:-true}" = "true" ]; then
      echo -e "${YELLOW}Destroying created GCP GCS bucket${NC}"
      TF_VAR_project_id="${GCP_PROJECT}" \
      TF_VAR_region="${GCP_REGION}" \
      TF_VAR_bucket_name="${GCP_BUCKET_NAME:-}" \
      TF_VAR_create_bucket="true" \
      terraform destroy -auto-approve
    else
      echo -e "${YELLOW}GCP GCS bucket is existing - nothing to destroy${NC}"
    fi
  elif [ "$tf_dir" = "$AZURE_TF_DIR" ]; then
    # For Azure: only destroy resources that were created (not existing ones)
    local targets=""

    # Only target container if we created it
    if [ "${AZURE_CREATE_CONTAINER:-true}" = "true" ]; then
      targets="$targets -target=azurerm_storage_data_lake_gen2_filesystem.tableflow"
    fi

    # Only target storage account if we created it
    if [ "${AZURE_CREATE_STORAGE_ACCOUNT:-true}" = "true" ]; then
      targets="$targets -target=azurerm_storage_account.ws"
    fi

    # Only target resource group if we created it
    if [ "${AZURE_CREATE_RESOURCE_GROUP:-true}" = "true" ]; then
      targets="$targets -target=azurerm_resource_group.ws"
    fi

    if [ -n "$targets" ]; then
      echo -e "${YELLOW}Destroying only created Azure resources (not existing ones)${NC}"
      TF_VAR_location="${TABLEFLOW_REGION:-eastus}" \
      TF_VAR_resource_group_name="${AZURE_RESOURCE_GROUP:-warpstream-tableflow-demo}" \
      TF_VAR_create_resource_group="${AZURE_CREATE_RESOURCE_GROUP:-true}" \
      TF_VAR_owner_email="${AZURE_OWNER_EMAIL:-}" \
      TF_VAR_storage_account_name="${AZURE_STORAGE_ACCOUNT:-wstableflowdemo}" \
      TF_VAR_create_storage_account="${AZURE_CREATE_STORAGE_ACCOUNT:-true}" \
      TF_VAR_container_name="${AZURE_CONTAINER:-tableflow}" \
      TF_VAR_create_container="${AZURE_CREATE_CONTAINER:-true}" \
      terraform destroy -auto-approve $targets
    else
      echo -e "${YELLOW}All Azure resources are existing - nothing to destroy${NC}"
    fi
  else
    terraform destroy -auto-approve
  fi
  destroy_rc=$?
  set -e

  popd >/dev/null

  if [ "$destroy_rc" -eq 0 ]; then
    echo -e "${GREEN}✓ ${label}: terraform destroy completed${NC}"
    if [ "$tf_dir" = "$WARPSTREAM_TF_DIR" ]; then
      TF_DESTROY_SUCCESS_WARPSTREAM=true
    elif [ "$tf_dir" = "$AZURE_TF_DIR" ]; then
      TF_DESTROY_SUCCESS_AZURE=true
    elif [ "$tf_dir" = "$TABLEFLOW_PIPELINE_TF_DIR" ]; then
      TF_DESTROY_SUCCESS_TABLEFLOW_PIPELINE=true
    fi
  else
    record_failure "${label}: terraform destroy failed"
    return 1
  fi
}
