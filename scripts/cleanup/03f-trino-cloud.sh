#!/bin/bash

################################################################################
# Script: 03f-trino-cloud.sh
# Description: Cleanup Trino resources for cloud backends (AWS/GCP)
################################################################################

run_cleanup_trino_cloud() {
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Cleanup: Trino Query Engine (Cloud Backend)${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local trino_namespace="trino"
  local namespace_timeout=10

  # Check if Trino namespace exists
  if ! kubectl get namespace "${trino_namespace}" >/dev/null 2>&1; then
    echo -e "${CYAN}Trino namespace not found - nothing to clean up${NC}"
    return 0
  fi

  # Stop Trino UI port-forward
  source "${SCRIPT_DIR}/scripts/common/port-forward.sh"
  stop_trino_ui_port_forward

  echo "Deleting Trino resources..."

  # Delete all standard resources
  echo "  Deleting pods, services, deployments..."
  kubectl -n "${trino_namespace}" delete all --all --grace-period=0 --force --ignore-not-found --timeout=30s || true
  kubectl -n "${trino_namespace}" delete secret --all --grace-period=0 --force --ignore-not-found --timeout=30s || true
  kubectl -n "${trino_namespace}" delete configmap --all --grace-period=0 --force --ignore-not-found --timeout=30s || true

  # Delete PVCs and wait for confirmation
  echo "  Deleting PVCs and waiting for removal..."
  kubectl -n "${trino_namespace}" delete pvc --all --grace-period=0 --force --ignore-not-found || true

  # Wait up to 60s for PVCs to be fully deleted
  local pvc_wait=0
  local pvc_max_wait=60
  while [ $pvc_wait -lt $pvc_max_wait ]; do
    remaining_pvcs=$(kubectl get pvc -n "${trino_namespace}" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [ "$remaining_pvcs" -eq 0 ]; then
      echo -e "${GREEN}    ✓ All PVCs deleted${NC}"
      break
    fi

    # Remove finalizers from stuck PVCs
    if [ $pvc_wait -gt 10 ]; then
      for pvc in $(kubectl get pvc -n "${trino_namespace}" -o name 2>/dev/null); do
        kubectl patch "$pvc" -n "${trino_namespace}" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
      done
    fi

    sleep 2
    pvc_wait=$((pvc_wait + 2))
  done

  if [ "$remaining_pvcs" -gt 0 ]; then
    echo -e "${YELLOW}    ⚠ ${remaining_pvcs} PVC(s) still terminating after ${pvc_max_wait}s${NC}"
  fi

  # Delete PVs that belong to Trino and wait for confirmation
  echo "  Deleting PVs..."
  local pv_list=$(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.claimRef.namespace == "'${trino_namespace}'") | .metadata.name' 2>/dev/null)

  if [ -n "$pv_list" ]; then
    for pv in $pv_list; do
      kubectl delete pv "$pv" --grace-period=0 --force 2>/dev/null || true
    done

    # Wait up to 30s for PVs to be fully deleted
    local pv_wait=0
    local pv_max_wait=30
    while [ $pv_wait -lt $pv_max_wait ]; do
      remaining_pvs=$(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.claimRef.namespace == "'${trino_namespace}'") | .metadata.name' 2>/dev/null | wc -l | tr -d ' ')
      if [ "$remaining_pvs" -eq 0 ]; then
        echo -e "${GREEN}    ✓ All PVs deleted${NC}"
        break
      fi

      # Remove finalizers from stuck PVs
      if [ $pv_wait -gt 10 ]; then
        for pv in $(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.claimRef.namespace == "'${trino_namespace}'") | .metadata.name' 2>/dev/null); do
          kubectl patch pv "$pv" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done
      fi

      sleep 2
      pv_wait=$((pv_wait + 2))
    done

    if [ "$remaining_pvs" -gt 0 ]; then
      echo -e "${YELLOW}    ⚠ ${remaining_pvs} PV(s) still terminating after ${pv_max_wait}s${NC}"
    fi
  else
    echo -e "${CYAN}    No PVs found${NC}"
  fi

  # Remove finalizers from namespace
  kubectl get namespace "${trino_namespace}" -o json 2>/dev/null | \
    jq '.spec.finalizers = []' 2>/dev/null | \
    kubectl replace --raw "/api/v1/namespaces/${trino_namespace}/finalize" -f - 2>/dev/null || true

  # Initiate namespace deletion
  echo "  Deleting namespace (waiting max ${namespace_timeout}s)..."
  kubectl delete namespace "${trino_namespace}" --grace-period=0 --force --ignore-not-found --wait=false || true

  # Wait up to 10s for namespace deletion
  local ns_wait=0
  while [ $ns_wait -lt $namespace_timeout ]; do
    if ! kubectl get namespace "${trino_namespace}" >/dev/null 2>&1; then
      echo -e "${GREEN}    ✓ Namespace deleted${NC}"
      return 0
    fi
    sleep 1
    ns_wait=$((ns_wait + 1))
  done

  # Namespace still exists after timeout
  echo -e "${YELLOW}    ⚠ Namespace still terminating (continuing cleanup)${NC}"
}
