#!/bin/bash
# Kubernetes helper functions

wait_for_namespace_deletion() {
  local namespace="$1"
  local timeout_seconds="${2:-$NAMESPACE_DELETE_TIMEOUT_SECONDS}"
  local poll_interval=5
  local deadline=$((SECONDS + timeout_seconds))
  local warned_pending=false

  while kubectl get namespace "$namespace" >/dev/null 2>&1; do
    if [ "$warned_pending" = false ] && [ "$SECONDS" -ge $((deadline - timeout_seconds + 30)) ]; then
      local ns_phase
      ns_phase="$(kubectl get namespace "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
      if [ "$ns_phase" = "Terminating" ]; then
        local terminating_resources
        terminating_resources="$(kubectl get all -n "$namespace" --ignore-not-found 2>/dev/null | grep -ci 'Terminating' || true)"
        if [ -n "$terminating_resources" ] && [ "$terminating_resources" -gt 0 ]; then
          echo -e "${YELLOW}Warning: Namespace '${namespace}' deletion is still pending (${terminating_resources} resource(s) terminating).${NC}"
        else
          echo -e "${YELLOW}Warning: Namespace '${namespace}' deletion is still pending and appears in Terminating state.${NC}"
        fi
        echo -e "${YELLOW}Please verify in a few minutes that deletion completes successfully.${NC}"
        warned_pending=true
      fi
    fi

    if [ "$SECONDS" -ge "$deadline" ]; then
      record_pending_namespace "$namespace"
      return 0
    fi
    sleep "$poll_interval"
  done

  echo -e "${GREEN}✓ Namespace '${namespace}' fully deleted${NC}"
}

record_failure() {
  local message="$1"
  FAILURES+=("$message")
  echo -e "${RED}Warning: ${message}${NC}"
}

record_pending_namespace() {
  local namespace="$1"
  PENDING_NAMESPACES+=("$namespace")
  echo -e "${YELLOW}Warning: Namespace '${namespace}' is still terminating. Will verify later.${NC}"
}
