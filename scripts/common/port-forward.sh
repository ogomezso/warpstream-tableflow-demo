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

stop_trino_ui_port_forward() {
  local trino_port="${TRINO_UI_PORT:-8080}"

  # Find and kill any Trino UI port-forward processes
  local pids=$(pgrep -f "port-forward.*trino.*${trino_port}" 2>/dev/null)

  if [ -n "$pids" ]; then
    echo "Stopping Trino UI port-forward (port ${trino_port})..."
    echo "$pids" | xargs kill 2>/dev/null || true
    sleep 1
    echo -e "${GREEN}✓ Trino UI port-forward stopped${NC}"
  else
    echo -e "${YELLOW}No Trino UI port-forward found on port ${trino_port}${NC}"
  fi
}
