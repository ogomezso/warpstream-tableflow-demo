#!/bin/bash
# Module: Trino Cleanup

run_step_cleanup_trino() {
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Step: Cleaning up Trino${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  local trino_namespace="trino"

  # Check if Trino namespace exists
  if ! kubectl get namespace "${trino_namespace}" >/dev/null 2>&1; then
    echo -e "${YELLOW}Trino namespace not found, skipping...${NC}"
    echo
    return
  fi

  echo "Deleting Trino resources..."

  # Delete deployments
  kubectl delete deployment trino -n "${trino_namespace}" --ignore-not-found=true 2>&1 | grep -v "NotFound" || true
  kubectl delete deployment warpstream-iceberg-proxy -n "${trino_namespace}" --ignore-not-found=true 2>&1 | grep -v "NotFound" || true

  # Delete services
  kubectl delete service trino -n "${trino_namespace}" --ignore-not-found=true 2>&1 | grep -v "NotFound" || true
  kubectl delete service warpstream-iceberg-proxy -n "${trino_namespace}" --ignore-not-found=true 2>&1 | grep -v "NotFound" || true

  # Delete configmaps
  kubectl delete configmap trino-config -n "${trino_namespace}" --ignore-not-found=true 2>&1 | grep -v "NotFound" || true
  kubectl delete configmap warpstream-proxy-config -n "${trino_namespace}" --ignore-not-found=true 2>&1 | grep -v "NotFound" || true

  # Delete secrets
  kubectl delete secret warpstream-agent-apikey -n "${trino_namespace}" --ignore-not-found=true 2>&1 | grep -v "NotFound" || true

  # Delete namespace
  echo "Deleting Trino namespace..."
  if kubectl delete namespace "${trino_namespace}" --timeout="${NAMESPACE_DELETE_TIMEOUT_SECONDS}s" 2>&1 | tee /tmp/trino_delete.log | grep -q "deleted"; then
    echo -e "${GREEN}✓ Trino namespace deleted${NC}"
  else
    if grep -q "not found" /tmp/trino_delete.log; then
      echo -e "${YELLOW}Trino namespace not found${NC}"
    elif kubectl get namespace "${trino_namespace}" -o jsonpath='{.status.phase}' 2>/dev/null | grep -q "Terminating"; then
      echo -e "${YELLOW}Warning: Trino namespace is still terminating${NC}"
      PENDING_NAMESPACES+=("${trino_namespace}")
    else
      echo -e "${RED}✗ Failed to delete Trino namespace${NC}"
      FAILURES+=("Failed to delete Trino namespace")
    fi
  fi

  rm -f /tmp/trino_delete.log
  echo
}
