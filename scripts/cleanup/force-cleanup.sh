#!/bin/bash
################################################################################
# Script: force-cleanup.sh
# Description: Force cleanup of stuck resources that regular cleanup couldn't remove
# Usage: ./scripts/cleanup/force-cleanup.sh
# WARNING: This is an aggressive cleanup script. Use only if regular cleanup fails.
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/common/colors.sh"

echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${RED}WARNING: Force Cleanup - Aggressive Resource Removal${NC}"
echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}This script will forcefully remove all demo resources.${NC}"
echo -e "${YELLOW}Use this only if regular cleanup (./demo-cleanup.sh) failed.${NC}"
echo
read -p "Are you sure you want to continue? (yes/no): " -r
echo
if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
  echo "Aborted."
  exit 0
fi

# Function to remove finalizers from all resources in a namespace
remove_finalizers_from_namespace() {
  local ns="$1"

  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    return
  fi

  echo -e "${CYAN}Removing finalizers from namespace '$ns'...${NC}"

  # Remove finalizers from all resource types
  for kind in $(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null); do
    kubectl get "$kind" -n "$ns" -o name 2>/dev/null | while read -r resource; do
      kubectl patch "$resource" -n "$ns" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
    done
  done

  # Remove finalizers from namespace itself
  kubectl get namespace "$ns" -o json 2>/dev/null | \
    jq '.spec.finalizers = []' 2>/dev/null | \
    kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
}

# Function to force delete a namespace
force_delete_namespace() {
  local ns="$1"

  if ! kubectl get namespace "$ns" >/dev/null 2>&1; then
    echo -e "${CYAN}Namespace '$ns' not found - skipping${NC}"
    return
  fi

  echo -e "${YELLOW}Force deleting namespace '$ns'...${NC}"

  # Delete all resources
  kubectl -n "$ns" delete all --all --grace-period=0 --force --ignore-not-found --timeout=60s || true
  kubectl -n "$ns" delete pvc --all --grace-period=0 --force --ignore-not-found --timeout=60s || true
  kubectl -n "$ns" delete secret --all --grace-period=0 --force --ignore-not-found --timeout=30s || true
  kubectl -n "$ns" delete configmap --all --grace-period=0 --force --ignore-not-found --timeout=30s || true

  # Remove finalizers
  remove_finalizers_from_namespace "$ns"

  # Delete namespace
  kubectl delete namespace "$ns" --grace-period=0 --force --ignore-not-found || true

  # Wait a moment
  sleep 2

  # Check status
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    status=$(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    echo -e "${YELLOW}  Namespace '$ns' status: $status${NC}"
  else
    echo -e "${GREEN}  ✓ Namespace '$ns' deleted${NC}"
  fi
}

# Cleanup each namespace
for ns in warpstream confluent trino minio; do
  force_delete_namespace "$ns"
  echo
done

# Force cleanup PVs
echo -e "${YELLOW}Force cleaning up PVs...${NC}"
for pv in $(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.claimRef.namespace | test("warpstream|confluent|trino|minio")) | .metadata.name' 2>/dev/null); do
  echo "  Deleting PV: $pv"
  kubectl patch pv "$pv" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
  kubectl delete pv "$pv" --grace-period=0 --force --timeout=30s || true
done

# Force cleanup Helm releases
echo
echo -e "${YELLOW}Force cleaning up Helm releases...${NC}"
for release_info in $(helm list --all-namespaces -o json 2>/dev/null | jq -r '.[] | select(.name | test("warpstream|confluent")) | "\(.name):\(.namespace)"' 2>/dev/null); do
  release=$(echo "$release_info" | cut -d: -f1)
  ns=$(echo "$release_info" | cut -d: -f2)
  echo "  Uninstalling Helm release: $release (namespace: $ns)"
  helm uninstall "$release" -n "$ns" --wait=false || true
done

echo
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Force cleanup completed${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo
echo "Run the verification script to check for remaining resources:"
echo "  ./scripts/cleanup/verify-cleanup.sh"
