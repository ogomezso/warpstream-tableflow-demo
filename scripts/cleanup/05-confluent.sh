#!/bin/bash
# Module: Confluent Resources Deletion
# Step 5/6 of demo cleanup

delete_confluent_resources() {
  # Check if we should remove Confluent resources
  # CLEANUP_REMOVE_CFK_OPERATOR controls removal of both Confluent resources AND CFK operator
  # Default is to remove (true) unless explicitly set to false
  if [ "$CLEANUP_REMOVE_CFK_OPERATOR" = "false" ]; then
    echo -e "${YELLOW}Confluent resources cleanup skipped (CLEANUP_REMOVE_CFK_OPERATOR=false)${NC}"
    return
  fi

  local namespace_timeout=10

  echo "Deleting Confluent Platform resources..."

  # Delete Confluent resources
  if kubectl get namespace "$CONFLUENT_NAMESPACE" >/dev/null 2>&1; then
    echo "  Deleting CFK CRDs..."
    kubectl -n "$CONFLUENT_NAMESPACE" delete kafka,connect,schemaregistry,controlcenter,ksqldb,zookeeper,kraftcontroller --all --grace-period=0 --force --ignore-not-found --timeout=30s || true

    echo "  Deleting pods, services, deployments..."
    kubectl -n "$CONFLUENT_NAMESPACE" delete all --all --grace-period=0 --force --ignore-not-found --timeout=30s || true
    kubectl -n "$CONFLUENT_NAMESPACE" delete secret --all --grace-period=0 --force --ignore-not-found --timeout=30s || true
    kubectl -n "$CONFLUENT_NAMESPACE" delete configmap --all --grace-period=0 --force --ignore-not-found --timeout=30s || true

    # Delete PVCs and wait for confirmation
    echo "  Deleting PVCs and waiting for removal..."
    kubectl -n "$CONFLUENT_NAMESPACE" delete pvc --all --grace-period=0 --force --ignore-not-found || true

    # Wait up to 60s for PVCs to be fully deleted
    local pvc_wait=0
    local pvc_max_wait=60
    while [ $pvc_wait -lt $pvc_max_wait ]; do
      remaining_pvcs=$(kubectl get pvc -n "$CONFLUENT_NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
      if [ "$remaining_pvcs" -eq 0 ]; then
        echo -e "${GREEN}    ✓ All PVCs deleted${NC}"
        break
      fi

      # Remove finalizers from stuck resources after 10s
      if [ $pvc_wait -gt 10 ]; then
        for kind in kafka connect schemaregistry controlcenter ksqldb zookeeper kraftcontroller; do
          for resource in $(kubectl get "$kind" -n "$CONFLUENT_NAMESPACE" -o name 2>/dev/null); do
            kubectl patch "$resource" -n "$CONFLUENT_NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
          done
        done

        for pvc in $(kubectl get pvc -n "$CONFLUENT_NAMESPACE" -o name 2>/dev/null); do
          kubectl patch "$pvc" -n "$CONFLUENT_NAMESPACE" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
        done
      fi

      sleep 2
      pvc_wait=$((pvc_wait + 2))
    done

    if [ "$remaining_pvcs" -gt 0 ]; then
      echo -e "${YELLOW}    ⚠ ${remaining_pvcs} PVC(s) still terminating after ${pvc_max_wait}s${NC}"
    fi

    # Delete PVs that belong to Confluent and wait for confirmation
    echo "  Deleting PVs..."
    local pv_list=$(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.claimRef.namespace == "'$CONFLUENT_NAMESPACE'") | .metadata.name' 2>/dev/null)

    if [ -n "$pv_list" ]; then
      for pv in $pv_list; do
        kubectl delete pv "$pv" --grace-period=0 --force 2>/dev/null || true
      done

      # Wait up to 30s for PVs to be fully deleted
      local pv_wait=0
      local pv_max_wait=30
      while [ $pv_wait -lt $pv_max_wait ]; do
        remaining_pvs=$(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.claimRef.namespace == "'$CONFLUENT_NAMESPACE'") | .metadata.name' 2>/dev/null | wc -l | tr -d ' ')
        if [ "$remaining_pvs" -eq 0 ]; then
          echo -e "${GREEN}    ✓ All PVs deleted${NC}"
          break
        fi

        # Remove finalizers from stuck PVs
        if [ $pv_wait -gt 10 ]; then
          for pv in $(kubectl get pv -o json 2>/dev/null | jq -r '.items[] | select(.spec.claimRef.namespace == "'$CONFLUENT_NAMESPACE'") | .metadata.name' 2>/dev/null); do
            kubectl patch pv "$pv" -p '{"metadata":{"finalizers":[]}}' --type=merge 2>/dev/null || true
          done
        fi

        sleep 2
        pv_wait=$((pv_wait + 2))
      done

      if [ "$remaining_pvs" -gt 0 ]; then
        echo -e "${YELLOW}    ⚠ ${remaining_pvs} PV(s) still terminating after ${pv_max_wait}s${NC}"
      fi
    else
      echo -e "${CYAN}    No PVs found${NC}"
    fi

    # Remove finalizers from namespace
    kubectl get namespace "$CONFLUENT_NAMESPACE" -o json 2>/dev/null | \
      jq '.spec.finalizers = []' 2>/dev/null | \
      kubectl replace --raw "/api/v1/namespaces/$CONFLUENT_NAMESPACE/finalize" -f - 2>/dev/null || true

    # Initiate namespace deletion
    echo "  Deleting namespace (waiting max ${namespace_timeout}s)..."
    kubectl delete namespace "$CONFLUENT_NAMESPACE" --grace-period=0 --force --ignore-not-found --wait=false || true

    # Wait up to 10s for namespace deletion
    local ns_wait=0
    while [ $ns_wait -lt $namespace_timeout ]; do
      if ! kubectl get namespace "$CONFLUENT_NAMESPACE" >/dev/null 2>&1; then
        echo -e "${GREEN}    ✓ Namespace deleted${NC}"
        break
      fi
      sleep 1
      ns_wait=$((ns_wait + 1))
    done

    if kubectl get namespace "$CONFLUENT_NAMESPACE" >/dev/null 2>&1; then
      echo -e "${YELLOW}    ⚠ Namespace still terminating (continuing cleanup)${NC}"
    fi
  else
    echo -e "${CYAN}Confluent namespace not found - nothing to clean up${NC}"
  fi

  # Remove CFK operator
  echo "Deleting CFK operator..."
  if helm status "$CFK_RELEASE" -n "$CFK_NAMESPACE" >/dev/null 2>&1; then
    helm uninstall "$CFK_RELEASE" -n "$CFK_NAMESPACE" --wait=false || true
    echo -e "${GREEN}✓ CFK operator release removed${NC}"
  else
    echo -e "${CYAN}CFK operator release not found - nothing to clean up${NC}"
  fi

  if kubectl get namespace "$CFK_NAMESPACE" >/dev/null 2>&1; then
    # Only clean up if different from Confluent namespace to avoid duplicate work
    if [ "$CFK_NAMESPACE" != "$CONFLUENT_NAMESPACE" ]; then
      echo "  Deleting CFK namespace resources..."
      kubectl -n "$CFK_NAMESPACE" delete all --all --grace-period=0 --force --ignore-not-found --timeout=30s || true
      kubectl -n "$CFK_NAMESPACE" delete secret --all --grace-period=0 --force --ignore-not-found --timeout=30s || true
      kubectl -n "$CFK_NAMESPACE" delete configmap --all --grace-period=0 --force --ignore-not-found --timeout=30s || true

      # Remove finalizers from namespace
      kubectl get namespace "$CFK_NAMESPACE" -o json 2>/dev/null | \
        jq '.spec.finalizers = []' 2>/dev/null | \
        kubectl replace --raw "/api/v1/namespaces/$CFK_NAMESPACE/finalize" -f - 2>/dev/null || true

      # Initiate namespace deletion
      echo "  Deleting CFK namespace (waiting max ${namespace_timeout}s)..."
      kubectl delete namespace "$CFK_NAMESPACE" --grace-period=0 --force --ignore-not-found --wait=false || true

      # Wait up to 10s
      local ns_wait=0
      while [ $ns_wait -lt $namespace_timeout ]; do
        if ! kubectl get namespace "$CFK_NAMESPACE" >/dev/null 2>&1; then
          echo -e "${GREEN}    ✓ CFK namespace deleted${NC}"
          break
        fi
        sleep 1
        ns_wait=$((ns_wait + 1))
      done

      if kubectl get namespace "$CFK_NAMESPACE" >/dev/null 2>&1; then
        echo -e "${YELLOW}    ⚠ CFK namespace still terminating (continuing cleanup)${NC}"
      fi
    fi
  fi
}

run_step_confluent() {
  echo -e "${YELLOW}[5/6] Deleting Confluent resources...${NC}"
  delete_confluent_resources || true
}
