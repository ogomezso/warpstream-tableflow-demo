#!/bin/bash
################################################################################
# Script: verify-cleanup.sh
# Description: Verify all demo resources have been cleaned up
# Usage: ./scripts/cleanup/verify-cleanup.sh
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${SCRIPT_DIR}/scripts/common/colors.sh"

echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}Verifying Demo Cleanup${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo

ISSUES_FOUND=0

# Check Kubernetes namespaces
echo -e "${CYAN}Checking Kubernetes namespaces...${NC}"
for ns in warpstream confluent trino minio; do
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    status=$(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    if [ "$status" = "Terminating" ]; then
      echo -e "${YELLOW}  ⚠ Namespace '$ns' is still terminating${NC}"

      # Show stuck resources
      stuck_resources=$(kubectl get all -n "$ns" 2>/dev/null | tail -n +2 || echo "")
      if [ -n "$stuck_resources" ]; then
        echo -e "${YELLOW}    Stuck resources:${NC}"
        kubectl get all -n "$ns" 2>/dev/null | head -10
      fi

      # Show finalizers
      finalizers=$(kubectl get namespace "$ns" -o jsonpath='{.spec.finalizers}' 2>/dev/null || echo "")
      if [ -n "$finalizers" ] && [ "$finalizers" != "[]" ]; then
        echo -e "${YELLOW}    Namespace finalizers: $finalizers${NC}"
      fi

      ISSUES_FOUND=$((ISSUES_FOUND + 1))
    else
      echo -e "${RED}  ✗ Namespace '$ns' still exists (status: $status)${NC}"
      ISSUES_FOUND=$((ISSUES_FOUND + 1))
    fi
  else
    echo -e "${GREEN}  ✓ Namespace '$ns' deleted${NC}"
  fi
done

echo

# Check for stuck PVCs
echo -e "${CYAN}Checking for stuck PVCs...${NC}"
stuck_pvcs=$(kubectl get pvc --all-namespaces 2>/dev/null | grep -E "(warpstream|confluent|trino|minio)" || echo "")
if [ -n "$stuck_pvcs" ]; then
  echo -e "${RED}  ✗ Found stuck PVCs:${NC}"
  kubectl get pvc --all-namespaces | grep -E "(warpstream|confluent|trino|minio)" || true
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
  echo -e "${GREEN}  ✓ No stuck PVCs${NC}"
fi

echo

# Check for stuck PVs
echo -e "${CYAN}Checking for stuck PVs...${NC}"
stuck_pvs=$(kubectl get pv 2>/dev/null | grep -E "(warpstream|confluent|trino|minio)" || echo "")
if [ -n "$stuck_pvs" ]; then
  echo -e "${RED}  ✗ Found stuck PVs:${NC}"
  kubectl get pv | grep -E "(warpstream|confluent|trino|minio)" || true
  ISSUES_FOUND=$((ISSUES_FOUND + 1))
else
  echo -e "${GREEN}  ✓ No stuck PVs${NC}"
fi

echo

# Check Helm releases
echo -e "${CYAN}Checking Helm releases...${NC}"
for release in warpstream-agent confluent-operator; do
  if helm list --all-namespaces 2>/dev/null | grep -q "$release"; then
    echo -e "${RED}  ✗ Helm release '$release' still exists${NC}"
    helm list --all-namespaces | grep "$release" || true
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
  else
    echo -e "${GREEN}  ✓ Helm release '$release' removed${NC}"
  fi
done

echo

# Check Terraform state files
echo -e "${CYAN}Checking Terraform state files...${NC}"
for tf_dir in environment/azure environment/aws environment/gcp environment/warpstream/cluster environment/warpstream/tableflow-pipeline; do
  tf_path="${SCRIPT_DIR}/${tf_dir}"
  if [ -d "$tf_path" ]; then
    if [ -f "${tf_path}/terraform.tfstate" ]; then
      # Check if state is empty
      resources=$(terraform -chdir="$tf_path" state list 2>/dev/null | wc -l || echo "0")
      if [ "$resources" -gt 0 ]; then
        echo -e "${YELLOW}  ⚠ Terraform state in '$tf_dir' still has $resources resource(s)${NC}"
        echo -e "${YELLOW}    Run: terraform -chdir=$tf_path state list${NC}"
        ISSUES_FOUND=$((ISSUES_FOUND + 1))
      else
        echo -e "${GREEN}  ✓ Terraform state in '$tf_dir' is empty${NC}"
      fi
    else
      echo -e "${GREEN}  ✓ No Terraform state in '$tf_dir'${NC}"
    fi
  fi
done

echo

# Summary
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
if [ $ISSUES_FOUND -eq 0 ]; then
  echo -e "${GREEN}✓ Cleanup verification passed - no issues found${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  exit 0
else
  echo -e "${RED}✗ Cleanup verification found $ISSUES_FOUND issue(s)${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo -e "${YELLOW}Suggested remediation steps:${NC}"
  echo -e "  1. Re-run cleanup: ./demo-cleanup.sh"
  echo -e "  2. Force cleanup stuck resources: ./scripts/cleanup/force-cleanup.sh"
  echo -e "  3. Manually remove finalizers from stuck resources"
  echo
  exit 1
fi
