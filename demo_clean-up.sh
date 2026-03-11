#!/bin/bash

################################################################################
# Script: demo_clean-up.sh
# Description: Tear down resources/files created by run_demo.sh
# Usage: ./demo_clean-up.sh
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
CLEANUP_REMOVE_CFK_OPERATOR="${CLEANUP_REMOVE_CFK_OPERATOR:-true}"

AZURE_TF_DIR="${SCRIPT_DIR}/environment/azure"
WARPSTREAM_TF_DIR="${SCRIPT_DIR}/environment/warpstream/cluster"

WARPSTREAM_AGENT_FILE="${SCRIPT_DIR}/environment/warpstream/warpstream-agent.yaml"
WARPSTREAM_NAMESPACE="${WARPSTREAM_NAMESPACE:-warpstream}"
WARPSTREAM_HELM_RELEASE="${WARPSTREAM_HELM_RELEASE:-warpstream-agent}"
NAMESPACE_DELETE_TIMEOUT_SECONDS="${NAMESPACE_DELETE_TIMEOUT_SECONDS:-30}"

WARPSTREAM_DEPLOY_API_KEY="${WARPSTREAM_DEPLOY_API_KEY:-${WARPSTREAM_API_KEY:-}}"
FAILURES=()
PENDING_NAMESPACES=()

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}Error: Required command not found: $1${NC}"
    exit 1
  fi
}

record_failure() {
  local message="$1"
  FAILURES+=("$message")
  echo -e "${RED}Warning: ${message}${NC}"
}

record_pending_namespace() {
  local namespace="$1"
  PENDING_NAMESPACES+=("$namespace")
  echo -e "${YELLOW}Warning: Namespace '${namespace}' is still terminating. Will verify later.${NC}"
}

wait_for_namespace_deletion() {
  local namespace="$1"
  local timeout_seconds="${2:-$NAMESPACE_DELETE_TIMEOUT_SECONDS}"
  local poll_interval=5
  local deadline=$((SECONDS + timeout_seconds))
  local warned_pending=false

  while kubectl get namespace "$namespace" >/dev/null 2>&1; do
    # If namespace is still Terminating after a short period, surface a non-fatal warning.
    if [ "$warned_pending" = false ] && [ "$SECONDS" -ge $((deadline - timeout_seconds + 30)) ]; then
      local ns_phase
      ns_phase="$(kubectl get namespace "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      if [ "$ns_phase" = "Terminating" ]; then
        local terminating_resources
        terminating_resources="$(kubectl get all -n "$namespace" --ignore-not-found 2>/dev/null | grep -ci 'Terminating' || true)"
        if [ -n "$terminating_resources" ] && [ "$terminating_resources" -gt 0 ]; then
          echo -e "${YELLOW}Warning: Namespace '${namespace}' deletion is still pending (${terminating_resources} resource(s) terminating).${NC}"
        else
          echo -e "${YELLOW}Warning: Namespace '${namespace}' deletion is still pending and appears in Terminating state.${NC}"
        fi
        echo -e "${YELLOW}Please verify in a few minutes that deletion completes successfully.${NC}"
        warned_pending=true
      fi
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
      record_pending_namespace "$namespace"
      return 0
    fi
    sleep "$poll_interval"
  done

  echo -e "${GREEN}✓ Namespace '${namespace}' fully deleted${NC}"
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

  while [[ "${WARPSTREAM_DEPLOY_API_KEY}" == aki_* ]]; do
    echo -e "${RED}Error: WARPSTREAM_DEPLOY_API_KEY looks like an agent key (starts with 'aki_').${NC}"
    echo -e "${YELLOW}Please provide a WarpStream account API key/token for Terraform provider auth.${NC}"
    prompt_for_env_var "WARPSTREAM_DEPLOY_API_KEY" "Enter WARPSTREAM_DEPLOY_API_KEY (account API key): " "true"
  done
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
    TF_VAR_warpstream_api_key="$WARPSTREAM_DEPLOY_API_KEY" terraform destroy -refresh=false -auto-approve
  else
    terraform destroy -refresh=false -auto-approve
  fi
  destroy_rc=$?
  set -e

  popd >/dev/null

  if [ "$destroy_rc" -eq 0 ]; then
    echo -e "${GREEN}✓ ${label}: terraform destroy completed${NC}"
  else
    record_failure "${label}: terraform destroy failed"
    return 1
  fi
}

delete_warpstream_k8s_resources() {
  if helm status "$WARPSTREAM_HELM_RELEASE" -n "$WARPSTREAM_NAMESPACE" >/dev/null 2>&1; then
    if helm uninstall "$WARPSTREAM_HELM_RELEASE" -n "$WARPSTREAM_NAMESPACE"; then
      echo -e "${GREEN}✓ WarpStream Helm release removed${NC}"
    else
      record_failure "WarpStream Helm release uninstall failed"
    fi
  else
    echo -e "${YELLOW}WarpStream Helm release not found; skipping uninstall.${NC}"
  fi

  kubectl -n "$WARPSTREAM_NAMESPACE" delete secret warpstream-agent-credentials --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$WARPSTREAM_NAMESPACE" delete secret azure-storage-credentials --ignore-not-found >/dev/null 2>&1 || true
  kubectl -n "$WARPSTREAM_NAMESPACE" delete secret warpstream-agent-apikey --ignore-not-found >/dev/null 2>&1 || true
  echo -e "${GREEN}✓ WarpStream secrets removed (if present)${NC}"

  if kubectl get namespace "$WARPSTREAM_NAMESPACE" >/dev/null 2>&1; then
    if kubectl delete namespace "$WARPSTREAM_NAMESPACE" --wait=false >/dev/null 2>&1; then
      wait_for_namespace_deletion "$WARPSTREAM_NAMESPACE" || true
    else
      record_failure "WarpStream namespace '${WARPSTREAM_NAMESPACE}' delete timed out or failed"
    fi
  else
    echo -e "${YELLOW}WarpStream namespace '${WARPSTREAM_NAMESPACE}' not found; skipping.${NC}"
  fi
}

delete_confluent_resources() {
  if [ -f "$CONFLUENT_CR_FILE" ]; then
    if kubectl delete -f "$CONFLUENT_CR_FILE" --ignore-not-found >/dev/null 2>&1; then
      echo -e "${GREEN}✓ Confluent resources deleted from manifest (if present)${NC}"
    else
      record_failure "Confluent manifest delete failed"
    fi
  fi

  if kubectl get namespace "$CONFLUENT_NAMESPACE" >/dev/null 2>&1; then
    if kubectl delete namespace "$CONFLUENT_NAMESPACE" --wait=false >/dev/null 2>&1; then
      wait_for_namespace_deletion "$CONFLUENT_NAMESPACE" || true
    else
      record_failure "Confluent namespace delete failed"
    fi
  elif kubectl delete namespace "$CONFLUENT_NAMESPACE" --ignore-not-found >/dev/null 2>&1; then
    echo -e "${YELLOW}Confluent namespace '${CONFLUENT_NAMESPACE}' not found; skipping.${NC}"
  else
    record_failure "Confluent namespace delete failed"
  fi

  if [ "$CLEANUP_REMOVE_CFK_OPERATOR" = "true" ]; then
    if helm status "$CFK_RELEASE" -n "$CFK_NAMESPACE" >/dev/null 2>&1; then
      if helm uninstall "$CFK_RELEASE" -n "$CFK_NAMESPACE"; then
        echo -e "${GREEN}✓ CFK operator release removed${NC}"
      else
        record_failure "CFK operator uninstall failed"
      fi
    else
      echo -e "${YELLOW}CFK operator release not found; skipping.${NC}"
    fi

    if kubectl get namespace "$CFK_NAMESPACE" >/dev/null 2>&1; then
      if kubectl delete namespace "$CFK_NAMESPACE" --wait=false >/dev/null 2>&1; then
        wait_for_namespace_deletion "$CFK_NAMESPACE" || true
      else
        record_failure "CFK namespace delete failed"
      fi
    elif kubectl delete namespace "$CFK_NAMESPACE" --ignore-not-found >/dev/null 2>&1; then
      echo -e "${YELLOW}CFK namespace '${CFK_NAMESPACE}' not found; skipping.${NC}"
    else
      record_failure "CFK namespace delete failed"
    fi
  else
    echo -e "${YELLOW}CFK operator cleanup skipped (set CLEANUP_REMOVE_CFK_OPERATOR=true to remove it).${NC}"
  fi
}

cleanup_generated_files() {
  rm -f "$WARPSTREAM_AGENT_FILE"
  rm -f "${WARPSTREAM_AGENT_FILE}.backup."*
  echo -e "${GREEN}✓ Generated WarpStream manifest/backups removed${NC}"

  # Remove Terraform init dirs and state files left after destroy
  for tf_dir in "$WARPSTREAM_TF_DIR" "$AZURE_TF_DIR"; do
    if [ -d "$tf_dir" ]; then
      rm -rf "${tf_dir}/.terraform"
      rm -f  "${tf_dir}/.terraform.lock.hcl"
      rm -f  "${tf_dir}/terraform.tfstate"
      rm -f  "${tf_dir}/terraform.tfstate.backup"
    fi
  done
  echo -e "${GREEN}✓ Terraform state and init dirs removed${NC}"
}

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Demo Cleanup: tear down run_demo.sh resources${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

require_cmd kubectl
require_cmd helm
require_cmd terraform
require_cmd az

echo -e "${YELLOW}[1/5] Validating credentials...${NC}"
ensure_azure_login
ensure_required_env_vars

echo -e "${YELLOW}[2/5] Removing WarpStream Kubernetes resources...${NC}"
delete_warpstream_k8s_resources || true

echo -e "${YELLOW}[3/5] Destroying Terraform resources...${NC}"
terraform_destroy_if_exists "$WARPSTREAM_TF_DIR" "WarpStream" || true
terraform_destroy_if_exists "$AZURE_TF_DIR" "Azure" || true

echo -e "${YELLOW}[4/5] Deleting Confluent resources...${NC}"
delete_confluent_resources || true

echo -e "${YELLOW}[5/5] Cleaning generated files...${NC}"
cleanup_generated_files

echo
if [ "${#FAILURES[@]}" -eq 0 ] && [ "${#PENDING_NAMESPACES[@]}" -eq 0 ]; then
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${GREEN}Demo Cleanup Complete${NC}"
  echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
elif [ "${#FAILURES[@]}" -eq 0 ]; then
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Demo Cleanup Complete (with pending namespace deletions)${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Warning: The following namespaces are still terminating:${NC}"
  for ns in "${PENDING_NAMESPACES[@]}"; do
    echo -e "${YELLOW}  - ${ns}${NC}"
  done
  echo -e "${YELLOW}Please verify these are fully deleted by running:${NC}"
  for ns in "${PENDING_NAMESPACES[@]}"; do
    echo "  kubectl get namespace ${ns}"
  done
else
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Demo Cleanup Completed With Failures${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo "Failures:"
  for failure in "${FAILURES[@]}"; do
    echo "- ${failure}"
  done
  if [ "${#PENDING_NAMESPACES[@]}" -gt 0 ]; then
    echo
    echo -e "${YELLOW}Warning: The following namespaces are still terminating:${NC}"
    for ns in "${PENDING_NAMESPACES[@]}"; do
      echo -e "${YELLOW}  - ${ns}${NC}"
    done
    echo -e "${YELLOW}Please verify these are fully deleted by running:${NC}"
    for ns in "${PENDING_NAMESPACES[@]}"; do
      echo "  kubectl get namespace ${ns}"
    done
  fi
  exit 1
fi
