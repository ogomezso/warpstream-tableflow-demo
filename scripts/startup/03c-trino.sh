#!/bin/bash
# Module: Trino Deployment for MinIO backend
# Step 3c/7 of demo startup (only when MinIO backend is selected)

setup_trino_ui_port_forward() {
  local trino_port="${TRINO_UI_PORT:-8080}"
  local trino_namespace="trino"

  # Check if port-forward is already running
  if pgrep -f "port-forward.*trino.*${trino_port}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Trino UI port-forward already running on port ${trino_port}${NC}"
    return
  fi

  # Start port-forward in background
  echo "Setting up Trino UI port-forward on port ${trino_port}..."
  kubectl port-forward -n "$trino_namespace" svc/trino "${trino_port}:8080" >/dev/null 2>&1 &
  local pf_pid=$!

  # Wait a moment and verify it started
  sleep 2
  if kill -0 "$pf_pid" 2>/dev/null; then
    echo -e "${GREEN}✓ Trino UI accessible at http://localhost:${trino_port}${NC}"
    echo -e "${YELLOW}  Port-forward running in background (PID: ${pf_pid})${NC}"
  else
    echo -e "${YELLOW}Warning: Port-forward may have failed to start${NC}"
  fi
}

run_step_trino() {
  echo -e "${YELLOW}[3c/7] Deploying Trino query engine...${NC}"

  local trino_dir="${SCRIPT_DIR}/environment/trino"
  local trino_namespace="trino"

  # Check if Trino is already deployed
  if kubectl get namespace "${trino_namespace}" >/dev/null 2>&1 && \
     kubectl get deployment trino -n "${trino_namespace}" >/dev/null 2>&1 && \
     kubectl get deployment trino -n "${trino_namespace}" -o jsonpath='{.status.availableReplicas}' | grep -q "^1$"; then
    echo -e "${GREEN}✓ Trino is already deployed and ready${NC}"
  else
    echo "Deploying Trino to Kubernetes..."
    bash "${trino_dir}/deploy-minio.sh"
    echo -e "${GREEN}✓ Trino deployed successfully${NC}"
  fi

  # Setup Trino UI port-forward
  setup_trino_ui_port_forward

  echo
}
