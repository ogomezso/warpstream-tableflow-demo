#!/bin/bash
# Common port-forward management functions

stop_control_center_port_forward() {
  local cc_port="${CONTROL_CENTER_PORT:-9021}"

  # Find and kill any Control Center port-forward processes
  local pids=$(pgrep -f "port-forward.*controlcenter.*${cc_port}" 2>/dev/null)

  if [ -n "$pids" ]; then
    echo "Stopping Control Center port-forward (port ${cc_port})..."
    echo "$pids" | xargs kill 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}✓ Control Center port-forward stopped${NC}"
  else
    echo -e "${YELLOW}No Control Center port-forward found on port ${cc_port}${NC}"
  fi
}

stop_minio_console_port_forward() {
  local minio_port="${MINIO_CONSOLE_PORT:-9001}"

  # Find and kill any MinIO console port-forward processes
  local pids=$(pgrep -f "port-forward.*minio.*${minio_port}" 2>/dev/null)

  if [ -n "$pids" ]; then
    echo "Stopping MinIO Console port-forward (port ${minio_port})..."
    echo "$pids" | xargs kill 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}✓ MinIO Console port-forward stopped${NC}"
  else
    echo -e "${YELLOW}No MinIO Console port-forward found on port ${minio_port}${NC}"
  fi
}

setup_trino_ui_port_forward() {
  local trino_port="${TRINO_UI_PORT:-8080}"
  local trino_namespace="trino"

  # Check if port-forward is already running
  if ps aux | grep -E "kubectl.*port-forward.*trino.*${trino_port}" | grep -v grep >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Trino UI port-forward already running on port ${trino_port}${NC}"
    return
  fi

  # Check if Trino service exists
  if ! kubectl get svc trino -n "$trino_namespace" >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: Trino service not found in namespace ${trino_namespace}${NC}"
    return 1
  fi

  # Start port-forward in background
  echo "Setting up Trino UI port-forward on port ${trino_port}..."
  kubectl port-forward -n "$trino_namespace" svc/trino "${trino_port}:8080" >/dev/null 2>&1 &
  local pf_pid=$!

  # Wait a moment and verify it started
  sleep 2
  if kill -0 "$pf_pid" 2>/dev/null; then
    echo -e "${GREEN}✓ Trino UI accessible at http://localhost:${trino_port}${NC}"
    echo -e "${CYAN}  Port-forward running in background (PID: ${pf_pid})${NC}"
  else
    echo -e "${YELLOW}Warning: Port-forward may have failed to start${NC}"
    return 1
  fi
}

stop_trino_ui_port_forward() {
  local trino_port="${TRINO_UI_PORT:-8080}"

  # Find and kill any Trino UI port-forward processes
  local pids=$(ps aux | grep -E "kubectl.*port-forward.*trino.*${trino_port}" | grep -v grep | awk '{print $2}')

  if [ -n "$pids" ]; then
    echo "Stopping Trino UI port-forward (port ${trino_port})..."
    echo "$pids" | xargs kill 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}✓ Trino UI port-forward stopped${NC}"
  else
    echo -e "${YELLOW}No Trino UI port-forward found on port ${trino_port}${NC}"
  fi
}
