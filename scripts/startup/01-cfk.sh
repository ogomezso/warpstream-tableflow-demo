#!/bin/bash
# Module: CFK Operator Installation
# Step 1/7 of demo startup

cfk_installed() {
  kubectl get deployment -A -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | grep -q '^confluent-operator$'
}

install_cfk_if_needed() {
  if cfk_installed; then
    echo -e "${GREEN}✓ CFK operator already installed${NC}"
    return
  fi

  echo -e "${YELLOW}CFK operator not found. Installing via Helm...${NC}"
  helm repo add "$CFK_HELM_REPO_NAME" "$CFK_HELM_REPO_URL" >/dev/null 2>&1 || true
  helm repo update >/dev/null
  helm upgrade --install "$CFK_RELEASE" "$CFK_HELM_CHART" \
    --namespace "$CFK_NAMESPACE" \
    --create-namespace

  kubectl rollout status deployment/confluent-operator -n "$CFK_NAMESPACE" --timeout="$CFK_ROLLOUT_TIMEOUT"
  echo -e "${GREEN}✓ CFK operator installed${NC}"
}

run_step_cfk() {
  echo -e "${YELLOW}[1/6] Checking/installing CFK operator...${NC}"
  install_cfk_if_needed
  echo
}
