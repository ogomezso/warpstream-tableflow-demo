#!/bin/bash
# Module: Confluent Resources Deletion
# Step 5/6 of demo cleanup

delete_confluent_resources() {
  if [ -f "$DATAGEN_CONNECTOR_FILE" ]; then
    if kubectl delete -f "$DATAGEN_CONNECTOR_FILE" --ignore-not-found >/dev/null 2>&1; then
      echo -e "${GREEN}✓ Datagen connector deleted (if present)${NC}"
    else
      record_failure "Datagen connector delete failed"
    fi
  fi

  if [ -f "$CONFLUENT_CR_FILE" ]; then
    if kubectl delete -f "$CONFLUENT_CR_FILE" --ignore-not-found >/dev/null 2>&1; then
      echo -e "${GREEN}✓ Confluent resources deleted from manifest (if present)${NC}"
    else
      record_failure "Confluent manifest delete failed"
    fi
  fi

  if kubectl get namespace "$CONFLUENT_NAMESPACE" >/dev/null 2>&1; then
    if kubectl delete namespace "$CONFLUENT_NAMESPACE" --wait=false >/dev/null 2>&1; then
      wait_for_namespace_deletion "$CONFLUENT_NAMESPACE" || true
    else
      record_failure "Confluent namespace delete failed"
    fi
  elif kubectl delete namespace "$CONFLUENT_NAMESPACE" --ignore-not-found >/dev/null 2>&1; then
    echo -e "${YELLOW}Confluent namespace '${CONFLUENT_NAMESPACE}' not found; skipping.${NC}"
  else
    record_failure "Confluent namespace delete failed"
  fi

  if [ "$CLEANUP_REMOVE_CFK_OPERATOR" = "true" ]; then
    if helm status "$CFK_RELEASE" -n "$CFK_NAMESPACE" >/dev/null 2>&1; then
      if helm uninstall "$CFK_RELEASE" -n "$CFK_NAMESPACE"; then
        echo -e "${GREEN}✓ CFK operator release removed${NC}"
      else
        record_failure "CFK operator uninstall failed"
      fi
    else
      echo -e "${YELLOW}CFK operator release not found; skipping.${NC}"
    fi

    if kubectl get namespace "$CFK_NAMESPACE" >/dev/null 2>&1; then
      if kubectl delete namespace "$CFK_NAMESPACE" --wait=false >/dev/null 2>&1; then
        wait_for_namespace_deletion "$CFK_NAMESPACE" || true
      else
        record_failure "CFK namespace delete failed"
      fi
    elif kubectl delete namespace "$CFK_NAMESPACE" --ignore-not-found >/dev/null 2>&1; then
      echo -e "${YELLOW}CFK namespace '${CFK_NAMESPACE}' not found; skipping.${NC}"
    else
      record_failure "CFK namespace delete failed"
    fi
  else
    echo -e "${YELLOW}CFK operator cleanup skipped (set CLEANUP_REMOVE_CFK_OPERATOR=true to remove it).${NC}"
  fi
}

run_step_confluent() {
  echo -e "${YELLOW}[5/6] Deleting Confluent resources...${NC}"
  delete_confluent_resources || true
}
