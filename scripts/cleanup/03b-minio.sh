#!/bin/bash
# Module: MinIO cleanup
# Step 3b of demo cleanup (cleanup MinIO if it was deployed)

run_step_cleanup_minio() {
  local minio_namespace="${MINIO_NAMESPACE:-minio}"

  # Check if MinIO namespace exists
  if ! kubectl get namespace "${minio_namespace}" >/dev/null 2>&1; then
    echo -e "${YELLOW}MinIO namespace '${minio_namespace}' does not exist, skipping cleanup${NC}"
    return
  fi

  echo -e "${YELLOW}[3b] Cleaning up MinIO resources...${NC}"

  # Delete MinIO resources
  echo "Deleting MinIO deployment..."
  kubectl delete -f "${SCRIPT_DIR}/environment/minio/deployment.yaml" --ignore-not-found=true || true
  kubectl delete -f "${SCRIPT_DIR}/environment/minio/init-job.yaml" --ignore-not-found=true || true

  # Delete namespace
  echo "Deleting MinIO namespace: ${minio_namespace}"
  kubectl delete namespace "${minio_namespace}" --wait=false --ignore-not-found=true || true

  # Wait for namespace deletion
  local wait_seconds=0
  while kubectl get namespace "${minio_namespace}" >/dev/null 2>&1; do
    if [ "$wait_seconds" -ge "$NAMESPACE_DELETE_TIMEOUT_SECONDS" ]; then
      echo -e "${YELLOW}Warning: Namespace '${minio_namespace}' is still terminating after ${NAMESPACE_DELETE_TIMEOUT_SECONDS}s${NC}"
      PENDING_NAMESPACES+=("${minio_namespace}")
      break
    fi
    echo "  Waiting for namespace '${minio_namespace}' to terminate... (${wait_seconds}s)"
    sleep 5
    wait_seconds=$((wait_seconds + 5))
  done

  if ! kubectl get namespace "${minio_namespace}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ MinIO namespace deleted${NC}"
  fi

  echo
}
