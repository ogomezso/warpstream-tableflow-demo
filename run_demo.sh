#!/bin/bash

################################################################################
# Script: run_demo.sh
# Description: End-to-end setup for CFK + Confluent + Azure + WarpStream agent
# Usage: ./run_demo.sh
################################################################################

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFLUENT_NAMESPACE="${CONFLUENT_NAMESPACE:-confluent}"
CONFLUENT_CR_FILE="${SCRIPT_DIR}/environment/confluent-platform/cp.yaml"

CFK_RELEASE="${CFK_RELEASE:-confluent-operator}"
CFK_NAMESPACE="${CFK_NAMESPACE:-confluent}"
CFK_HELM_REPO_NAME="${CFK_HELM_REPO_NAME:-confluentinc}"
CFK_HELM_REPO_URL="${CFK_HELM_REPO_URL:-https://packages.confluent.io/helm}"
CFK_HELM_CHART="${CFK_HELM_CHART:-confluentinc/confluent-for-kubernetes}"
CFK_ROLLOUT_TIMEOUT="${CFK_ROLLOUT_TIMEOUT:-300s}"
CP_READY_TIMEOUT="${CP_READY_TIMEOUT:-900s}"

AZURE_TF_DIR="${SCRIPT_DIR}/environment/azure"
WARPSTREAM_TF_DIR="${SCRIPT_DIR}/environment/warpstream/cluster"

WARPSTREAM_TEMPLATE_FILE="${SCRIPT_DIR}/environment/warpstream/warpstream-agent-template.yaml"
WARPSTREAM_AGENT_FILE="${SCRIPT_DIR}/environment/warpstream/warpstream-agent.yaml"
WARPSTREAM_NAMESPACE="${WARPSTREAM_NAMESPACE:-warpstream}"
WARPSTREAM_HELM_RELEASE="${WARPSTREAM_HELM_RELEASE:-warpstream-agent}"
WARPSTREAM_HELM_REPO_NAME="${WARPSTREAM_HELM_REPO_NAME:-warpstreamlabs}"
WARPSTREAM_HELM_REPO_URL="${WARPSTREAM_HELM_REPO_URL:-https://warpstreamlabs.github.io/charts}"
WARPSTREAM_HELM_CHART="${WARPSTREAM_HELM_CHART:-warpstreamlabs/warpstream-agent}"

TABLEFLOW_REGION="${TABLEFLOW_REGION:-eastus}"
WARPSTREAM_DEPLOY_API_KEY="${WARPSTREAM_DEPLOY_API_KEY:-${WARPSTREAM_API_KEY:-}}"
WARPSTREAM_AGENT_KEY_OVERRIDE="${WARPSTREAM_AGENT_KEY:-}"
DEBUG="${DEBUG:-false}"

is_debug_enabled() {
  case "${DEBUG}" in
    true|TRUE|1|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

debug_log() {
  if is_debug_enabled; then
    echo -e "${YELLOW}[DEBUG] $*${NC}"
  fi
}

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}Error: Required command not found: $1${NC}"
    exit 1
  fi
}

prompt_for_env_var() {
  local var_name="$1"
  local prompt_text="$2"
  local secret_input="${3:-false}"
  local value=""

  while [ -z "$value" ]; do
    if [ "$secret_input" = "true" ]; then
      read -r -s -p "$prompt_text" value
      echo
    else
      read -r -p "$prompt_text" value
    fi

    if [ -z "$value" ]; then
      echo -e "${YELLOW}Value cannot be empty. Please try again.${NC}"
    fi
  done

  export "$var_name=$value"
}

ensure_required_env_vars() {
  if [ -z "${WARPSTREAM_DEPLOY_API_KEY:-}" ]; then
    echo -e "${YELLOW}Required environment variable WARPSTREAM_DEPLOY_API_KEY is not set.${NC}"
    prompt_for_env_var "WARPSTREAM_DEPLOY_API_KEY" "Enter WARPSTREAM_DEPLOY_API_KEY (account API key): " "true"
  fi

  # Guardrail: Terraform provider requires an account API key, not an agent key.
  while [[ "${WARPSTREAM_DEPLOY_API_KEY}" == aki_* ]]; do
    echo -e "${RED}Error: WARPSTREAM_DEPLOY_API_KEY looks like an agent key (starts with 'aki_').${NC}"
    echo -e "${YELLOW}Please provide a WarpStream account API key/token for Terraform provider auth.${NC}"
    prompt_for_env_var "WARPSTREAM_DEPLOY_API_KEY" "Enter WARPSTREAM_DEPLOY_API_KEY (account API key): " "true"
  done

  # Optional override for the agent key (must be different from deploy key).
  if [ -n "${WARPSTREAM_AGENT_KEY_OVERRIDE:-}" ]; then
    if [[ "${WARPSTREAM_AGENT_KEY_OVERRIDE}" != aki_* ]]; then
      echo -e "${RED}Error: WARPSTREAM_AGENT_KEY must be an agent key starting with 'aki_'.${NC}"
      exit 1
    fi

    if [ "${WARPSTREAM_AGENT_KEY_OVERRIDE}" = "${WARPSTREAM_DEPLOY_API_KEY}" ]; then
      echo -e "${RED}Error: WARPSTREAM_AGENT_KEY must be different from WARPSTREAM_DEPLOY_API_KEY.${NC}"
      exit 1
    fi
  fi
}

ensure_azure_login() {
  if az account show >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Azure CLI already authenticated${NC}"
  else
    echo -e "${YELLOW}Azure CLI is not authenticated. Starting az login...${NC}"
    az login >/dev/null

    if ! az account show >/dev/null 2>&1; then
      echo -e "${RED}Error: Azure login failed. Run 'az login' and retry.${NC}"
      exit 1
    fi
  fi

  select_azure_subscription

  local account_name
  account_name="$(az account show --query name -o tsv 2>/dev/null || true)"
  echo -e "${GREEN}✓ Azure subscription selected${NC}${account_name:+ (${account_name})}"
}

select_azure_subscription() {
  local preset_subscription="${AZURE_SUBSCRIPTION_ID:-}"
  if [ -n "$preset_subscription" ]; then
    if az account set --subscription "$preset_subscription" >/dev/null 2>&1; then
      return
    fi
    echo -e "${RED}Error: AZURE_SUBSCRIPTION_ID is set but invalid: ${preset_subscription}${NC}"
    exit 1
  fi

  local subscriptions
  subscriptions="$(az account list --query "[?state=='Enabled'].[id,name]" -o tsv)"

  if [ -z "$subscriptions" ]; then
    echo -e "${RED}Error: No enabled Azure subscriptions found for this account.${NC}"
    exit 1
  fi

  local count
  count="$(printf '%s\n' "$subscriptions" | wc -l | tr -d ' ')"

  if [ "$count" -eq 1 ]; then
    local only_id
    only_id="$(printf '%s\n' "$subscriptions" | awk -F '\t' '{print $1}')"
    az account set --subscription "$only_id" >/dev/null
    export AZURE_SUBSCRIPTION_ID="$only_id"
    return
  fi

  echo -e "${YELLOW}Multiple Azure subscriptions detected. Choose one:${NC}"
  local i=1
  while IFS=$'\t' read -r sub_id sub_name; do
    echo "  ${i}) ${sub_name} (${sub_id})"
    i=$((i + 1))
  done <<< "$subscriptions"

  local choice=""
  while :; do
    read -r -p "Enter subscription number [1-${count}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
      break
    fi
    echo -e "${YELLOW}Invalid selection. Please enter a number between 1 and ${count}.${NC}"
  done

  local selected_line
  selected_line="$(printf '%s\n' "$subscriptions" | sed -n "${choice}p")"
  local selected_id
  selected_id="$(printf '%s\n' "$selected_line" | awk -F '\t' '{print $1}')"

  az account set --subscription "$selected_id" >/dev/null
  export AZURE_SUBSCRIPTION_ID="$selected_id"
}

validate_paths() {
  local path="$1"
  if [ ! -e "$path" ]; then
    echo -e "${RED}Error: Required path not found: $path${NC}"
    exit 1
  fi
}

cfk_installed() {
  kubectl get deployment -A -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | grep -q '^confluent-operator$'
}

install_cfk_if_needed() {
  if cfk_installed; then
    echo -e "${GREEN}✓ CFK operator already installed${NC}"
    return
  fi

  echo -e "${YELLOW}CFK operator not found. Installing via Helm...${NC}"
  helm repo add "$CFK_HELM_REPO_NAME" "$CFK_HELM_REPO_URL" >/dev/null 2>&1 || true
  helm repo update >/dev/null
  helm upgrade --install "$CFK_RELEASE" "$CFK_HELM_CHART" \
    --namespace "$CFK_NAMESPACE" \
    --create-namespace

  kubectl rollout status deployment/confluent-operator -n "$CFK_NAMESPACE" --timeout="$CFK_ROLLOUT_TIMEOUT"
  echo -e "${GREEN}✓ CFK operator installed${NC}"
}

wait_for_confluent_ready() {
  local waited=0
  local step=5
  local max_wait=300

  until [ "$(kubectl -n "$CONFLUENT_NAMESPACE" get pods --no-headers 2>/dev/null | wc -l | tr -d ' ')" -gt 0 ]; do
    if [ "$waited" -ge "$max_wait" ]; then
      echo -e "${RED}Error: No pods created in namespace '${CONFLUENT_NAMESPACE}' after ${max_wait}s.${NC}"
      exit 1
    fi
    sleep "$step"
    waited=$((waited + step))
  done

  kubectl -n "$CONFLUENT_NAMESPACE" wait --for=condition=Ready pod --all --timeout="$CP_READY_TIMEOUT"
}

terraform_apply_if_needed() {
  local tf_dir="$1"
  local label="$2"
  local plan_file=".run_demo.tfplan"

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

deploy_warpstream_agent() {
  local rendered_file="$1"
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  local values_file="${tmp_dir}/warpstream-agent-values.yaml"
  local manifest_file="${tmp_dir}/warpstream-agent-manifests.yaml"

  # Split mixed template: first YAML document is Helm values, the rest are Kubernetes manifests.
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

  if is_debug_enabled; then
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

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Run Demo: CFK + Confluent + WarpStream Tableflow${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

require_cmd kubectl
require_cmd helm
require_cmd terraform
require_cmd az

validate_paths "$CONFLUENT_CR_FILE"
validate_paths "$AZURE_TF_DIR"
validate_paths "$WARPSTREAM_TF_DIR"
validate_paths "$WARPSTREAM_TEMPLATE_FILE"

echo -e "${GREEN}✓ Prerequisites validated${NC}\n"

echo -e "${YELLOW}[1/4] Checking/installing CFK operator...${NC}"
install_cfk_if_needed
echo

echo -e "${YELLOW}[2/4] Installing Confluent Platform resources in namespace '${CONFLUENT_NAMESPACE}'...${NC}"
kubectl create namespace "$CONFLUENT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$CONFLUENT_CR_FILE"

# Wait until all pods in namespace are Ready before moving to Terraform resources.
wait_for_confluent_ready
echo -e "${GREEN}✓ Confluent Platform resources are up and ready${NC}\n"

echo -e "${YELLOW}[3/4] Applying Terraform resources only when needed...${NC}"
ensure_azure_login
ensure_required_env_vars
terraform_apply_if_needed "$AZURE_TF_DIR" "Azure"
terraform_apply_if_needed "$WARPSTREAM_TF_DIR" "WarpStream"
echo

echo -e "${YELLOW}[4/4] Rendering and deploying WarpStream agent...${NC}"
AZURE_STORAGE_ACCOUNT="$(terraform_output_raw "$AZURE_TF_DIR" "storage_account_name")"
AZURE_STORAGE_KEY="$(terraform_output_raw "$AZURE_TF_DIR" "storage_account_primary_access_key")"
TABLEFLOW_CONTAINER="$(terraform_output_raw "$AZURE_TF_DIR" "tableflow_container_name")"
BUCKET_URL="azblob://${TABLEFLOW_CONTAINER}"

if [ -n "${WARPSTREAM_AGENT_KEY_OVERRIDE:-}" ]; then
  WARPSTREAM_AGENT_KEY="${WARPSTREAM_AGENT_KEY_OVERRIDE}"
  echo -e "${YELLOW}Using WARPSTREAM_AGENT_KEY from environment override.${NC}"
else
  WARPSTREAM_AGENT_KEY="$(terraform_output_raw "$WARPSTREAM_TF_DIR" "tableflow_agent_key")"
fi
WARPSTREAM_VIRTUAL_CLUSTER_ID="$(terraform_output_raw "$WARPSTREAM_TF_DIR" "tableflow_virtual_cluster_id")"

if [ -z "$AZURE_STORAGE_ACCOUNT" ] || [ -z "$AZURE_STORAGE_KEY" ] || [ -z "$TABLEFLOW_CONTAINER" ] || [ -z "$WARPSTREAM_AGENT_KEY" ] || [ -z "$WARPSTREAM_VIRTUAL_CLUSTER_ID" ]; then
  echo -e "${RED}Error: One or more terraform outputs are empty.${NC}"
  if is_debug_enabled; then
    echo "Debug info:"
    echo "  AZURE_STORAGE_ACCOUNT: ${AZURE_STORAGE_ACCOUNT:-[empty]}"
    echo "  AZURE_STORAGE_KEY: ${AZURE_STORAGE_KEY:+[SET $((${#AZURE_STORAGE_KEY})) chars]}\${AZURE_STORAGE_KEY:-[empty]}"
    echo "  TABLEFLOW_CONTAINER: ${TABLEFLOW_CONTAINER:-[empty]}"
    echo "  WARPSTREAM_AGENT_KEY: ${WARPSTREAM_AGENT_KEY:-[empty]}"
    echo "  WARPSTREAM_VIRTUAL_CLUSTER_ID: ${WARPSTREAM_VIRTUAL_CLUSTER_ID:-[empty]}"
  fi
  exit 1
fi

# Validate agent key format
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
fi

BACKUP_FILE="${WARPSTREAM_AGENT_FILE}.backup.$(date +%s)"
if [ -f "$WARPSTREAM_AGENT_FILE" ]; then
  cp "$WARPSTREAM_AGENT_FILE" "$BACKUP_FILE"
fi

cp "$WARPSTREAM_TEMPLATE_FILE" "$WARPSTREAM_AGENT_FILE"

sed -i '' "s|<TABLEFLOW_CONTAINER>|${TABLEFLOW_CONTAINER}|g" "$WARPSTREAM_AGENT_FILE"
sed -i '' "s|<TABLEFLOW_VIRTUAL_CLUSTER_ID>|${WARPSTREAM_VIRTUAL_CLUSTER_ID}|g" "$WARPSTREAM_AGENT_FILE"
sed -i '' "s|<TABLEFLOW_REGION>|${TABLEFLOW_REGION}|g" "$WARPSTREAM_AGENT_FILE"
sed -i '' "s|<AZURE_STORAGE_ACCOUNT>|${AZURE_STORAGE_ACCOUNT}|g" "$WARPSTREAM_AGENT_FILE"
sed -i '' "s|<WARPSTREAM_AGENT_KEY>|${WARPSTREAM_AGENT_KEY}|g" "$WARPSTREAM_AGENT_FILE"
sed -i '' "s|<AZURE_STORAGE_KEY>|${AZURE_STORAGE_KEY}|g" "$WARPSTREAM_AGENT_FILE"

# Force bucket URL from terraform-derived container in case template format changes.
sed -i '' "s|bucketURL: .*|bucketURL: ${BUCKET_URL}|" "$WARPSTREAM_AGENT_FILE"

deploy_warpstream_agent "$WARPSTREAM_AGENT_FILE"

echo -e "${GREEN}✓ WarpStream agent deployed${NC}"
if [ -f "${BACKUP_FILE:-}" ]; then
  echo -e "${GREEN}✓ Backup created: ${BACKUP_FILE}${NC}"
fi

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Run Demo Complete${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

echo "Summary:"
echo "- Confluent namespace: ${CONFLUENT_NAMESPACE}"
echo "- CFK release: ${CFK_RELEASE}"
echo "- CFK namespace: ${CFK_NAMESPACE}"
echo "- Azure storage account: ${AZURE_STORAGE_ACCOUNT}"
echo "- Azure container: ${TABLEFLOW_CONTAINER}"
echo "- Bucket URL: ${BUCKET_URL}"
echo "- WarpStream virtual cluster ID: ${WARPSTREAM_VIRTUAL_CLUSTER_ID}"
echo "- WarpStream deploy key: [redacted]"
echo "- WarpStream agent key: [redacted]"
echo "- WarpStream namespace: ${WARPSTREAM_NAMESPACE}"
echo "- WarpStream Helm release: ${WARPSTREAM_HELM_RELEASE}"
echo "- Rendered file: ${WARPSTREAM_AGENT_FILE}"

if [ -z "${WARPSTREAM_DEPLOY_API_KEY:-}" ] && [ -z "${WARPSTREAM_API_KEY:-}" ]; then
  echo
  echo -e "${YELLOW}Note:${NC} Export a deploy API key before running:"
  echo "  export WARPSTREAM_DEPLOY_API_KEY='<your_warpstream_account_api_key>'"
fi

if [ -z "${WARPSTREAM_AGENT_KEY_OVERRIDE:-}" ]; then
  echo -e "${YELLOW}Info:${NC} Agent key will be created/read from Terraform output (resource: warpstream_agent_key.demo_agent_key)."
else
  echo -e "${YELLOW}Info:${NC} Agent key override was used from WARPSTREAM_AGENT_KEY."
fi
