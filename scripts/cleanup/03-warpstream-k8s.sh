#!/bin/bash
# Module: WarpStream Kubernetes Resources Removal
# Step 3/6 of demo cleanup

delete_warpstream_k8s_resources() {
  if helm status "$WARPSTREAM_HELM_RELEASE" -n "$WARPSTREAM_NAMESPACE" >/dev/null 2>&1; then
    if helm uninstall "$WARPSTREAM_HELM_RELEASE" -n "$WARPSTREAM_NAMESPACE" --wait=false; then
      echo -e "${GREEN}✓ WarpStream Helm release removed${NC}"
    else
      record_failure "WarpStream Helm release uninstall failed"
    fi
  else
    echo -e "${YELLOW}WarpStream Helm release not found; skipping uninstall.${NC}"
  fi

  # Force delete all resources in the namespace (with timeout)
  timeout 10s kubectl -n "$WARPSTREAM_NAMESPACE" delete all --all --grace-period=0 --force --ignore-not-found 2>/dev/null || true
  timeout 10s kubectl -n "$WARPSTREAM_NAMESPACE" delete secret --all --grace-period=0 --force --ignore-not-found 2>/dev/null || true
  timeout 10s kubectl -n "$WARPSTREAM_NAMESPACE" delete configmap --all --grace-period=0 --force --ignore-not-found 2>/dev/null || true
  timeout 10s kubectl -n "$WARPSTREAM_NAMESPACE" delete pvc --all --grace-period=0 --force --ignore-not-found 2>/dev/null || true
  echo -e "${GREEN}✓ WarpStream resources force deleted${NC}"

  if kubectl get namespace "$WARPSTREAM_NAMESPACE" >/dev/null 2>&1; then
    # Remove finalizers from namespace (with timeout)
    (
      timeout 5s kubectl get namespace "$WARPSTREAM_NAMESPACE" -o json 2>/dev/null | \
        jq '.spec.finalizers = []' 2>/dev/null | \
        timeout 5s kubectl replace --raw "/api/v1/namespaces/$WARPSTREAM_NAMESPACE/finalize" -f - 2>/dev/null
    ) || true

    # Force delete namespace
    timeout 10s kubectl delete namespace "$WARPSTREAM_NAMESPACE" --grace-period=0 --force --wait=false 2>/dev/null || true
    echo -e "${GREEN}✓ WarpStream namespace force deleted${NC}"
  else
    echo -e "${YELLOW}WarpStream namespace '${WARPSTREAM_NAMESPACE}' not found; skipping.${NC}"
  fi
}

run_step_warpstream_k8s() {
  echo -e "${YELLOW}[3/6] Removing WarpStream Kubernetes resources...${NC}"
  delete_warpstream_k8s_resources || true
}
