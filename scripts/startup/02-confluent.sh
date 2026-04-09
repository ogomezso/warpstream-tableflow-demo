#!/bin/bash
# Module: Confluent Platform Deployment
# Step 2/7 of demo startup

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

setup_control_center_port_forward() {
  local cc_port="${CONTROL_CENTER_PORT:-9021}"

  # Check if port-forward is already running
  if pgrep -f "port-forward.*controlcenter.*${cc_port}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Control Center port-forward already running on port ${cc_port}${NC}"
    return
  fi

  # Start port-forward in background
  echo "Setting up Control Center port-forward on port ${cc_port}..."
  kubectl port-forward -n "$CONFLUENT_NAMESPACE" svc/controlcenter-ng "${cc_port}:9021" >/dev/null 2>&1 &
  local pf_pid=$!

  # Wait a moment and verify it started
  sleep 2
  if kill -0 "$pf_pid" 2>/dev/null; then
    echo -e "${GREEN}✓ Control Center accessible at http://localhost:${cc_port}${NC}"
    echo -e "${YELLOW}  Port-forward running in background (PID: ${pf_pid})${NC}"
  else
    echo -e "${YELLOW}Warning: Port-forward may have failed to start${NC}"
  fi
}

run_step_confluent() {
  echo -e "${YELLOW}[2/7] Installing Confluent Platform resources in namespace '${CONFLUENT_NAMESPACE}'...${NC}"
  kubectl create namespace "$CONFLUENT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$CONFLUENT_CR_FILE"

  wait_for_confluent_ready
  echo -e "${GREEN}✓ Confluent Platform resources are up and ready${NC}"

  # Setup Control Center port-forward
  setup_control_center_port_forward
  echo
}
