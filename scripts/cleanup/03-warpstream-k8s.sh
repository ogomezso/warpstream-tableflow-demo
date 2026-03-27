#!/bin/bash
# Module: WarpStream Kubernetes Resources Removal
# Step 3/6 of demo cleanup

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

run_step_warpstream_k8s() {
  echo -e "${YELLOW}[3/6] Removing WarpStream Kubernetes resources...${NC}"
  delete_warpstream_k8s_resources || true
}
