#!/bin/bash
# Module: MinIO Deployment
# Step 3b/7 of demo startup (alternative to Azure - Step 4)

setup_minio_console_port_forward() {
  local minio_console_port="${MINIO_CONSOLE_PORT:-9001}"
  local minio_namespace="${MINIO_NAMESPACE:-minio}"

  # Check if port-forward is already running
  if pgrep -f "port-forward.*minio.*${minio_console_port}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ MinIO Console port-forward already running on port ${minio_console_port}${NC}"
    return
  fi

  # Start port-forward in background
  echo "Setting up MinIO Console port-forward on port ${minio_console_port}..."
  kubectl port-forward -n "$minio_namespace" svc/minio "${minio_console_port}:9001" >/dev/null 2>&1 &
  local pf_pid=$!

  # Wait a moment and verify it started
  sleep 2
  if kill -0 "$pf_pid" 2>/dev/null; then
    echo -e "${GREEN}✓ MinIO Console accessible at http://localhost:${minio_console_port}${NC}"
    echo -e "${YELLOW}  Credentials: minioadmin / minioadmin${NC}"
    echo -e "${YELLOW}  Port-forward running in background (PID: ${pf_pid})${NC}"
  else
    echo -e "${YELLOW}Warning: Port-forward may have failed to start${NC}"
  fi
}

run_step_minio() {
  echo -e "${YELLOW}[3b/7] Deploying MinIO backend...${NC}"

  local minio_dir="${SCRIPT_DIR}/environment/minio"
  local minio_namespace="${MINIO_NAMESPACE:-minio}"

  # Check if MinIO is already deployed
  if kubectl get namespace "${minio_namespace}" >/dev/null 2>&1 && \
     kubectl get deployment minio -n "${minio_namespace}" >/dev/null 2>&1 && \
     kubectl get deployment minio -n "${minio_namespace}" -o jsonpath='{.status.availableReplicas}' | grep -q "^1$"; then
    echo -e "${GREEN}✓ MinIO is already deployed and ready${NC}"
  else
    echo "Deploying MinIO to Kubernetes..."
    bash "${minio_dir}/deploy.sh"
    echo -e "${GREEN}✓ MinIO deployed successfully${NC}"
  fi

  # Export MinIO configuration for WarpStream agent
  export MINIO_BUCKET="tableflow"
  export MINIO_ACCESS_KEY="minioadmin"
  export MINIO_SECRET_KEY="minioadmin"
  export MINIO_ENDPOINT="http://minio.minio.svc.cluster.local:9000"

  # Setup MinIO Console port-forward
  setup_minio_console_port_forward

  echo
}
