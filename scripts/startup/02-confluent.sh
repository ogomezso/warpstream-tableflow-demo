#!/bin/bash
# Module: Confluent Platform Deployment
# Step 2/6 of demo startup

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

run_step_confluent() {
  echo -e "${YELLOW}[2/6] Installing Confluent Platform resources in namespace '${CONFLUENT_NAMESPACE}'...${NC}"
  kubectl create namespace "$CONFLUENT_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f "$CONFLUENT_CR_FILE"

  wait_for_confluent_ready
  echo -e "${GREEN}✓ Confluent Platform resources are up and ready${NC}\n"
}
