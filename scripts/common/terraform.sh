#!/bin/bash
# Terraform helper functions

terraform_apply_if_needed() {
  local tf_dir="$1"
  local label="$2"
  local plan_file=".demo-startup.tfplan"

  pushd "$tf_dir" >/dev/null
  terraform init -input=false >/dev/null

  set +e
  if [ "$tf_dir" = "$WARPSTREAM_TF_DIR" ]; then
    TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" terraform plan -input=false -detailed-exitcode -out="$plan_file" >/dev/null
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
    TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" terraform apply -auto-approve "$plan_file"
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
    TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" terraform destroy -auto-approve
  elif [ "$tf_dir" = "$TABLEFLOW_PIPELINE_TF_DIR" ]; then
    local vc_id=""
    if [ -d "$WARPSTREAM_TF_DIR" ]; then
      vc_id="$(cd "$WARPSTREAM_TF_DIR" && terraform output -raw tableflow_virtual_cluster_id 2>/dev/null || true)"
    fi
    TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" \
    TF_VAR_tableflow_virtual_cluster_id="$vc_id" \
    terraform destroy -auto-approve
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
