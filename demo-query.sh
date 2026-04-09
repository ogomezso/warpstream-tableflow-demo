#!/bin/bash

################################################################################
# Script: demo-query.sh
# Description: Query interface for WarpStream Tableflow demo
#              Routes to appropriate query engine based on deployment
# Usage: ./demo-query.sh [query-type]
################################################################################

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

########################################
# Source common modules
########################################

source "${SCRIPT_DIR}/scripts/common/colors.sh"
source "${SCRIPT_DIR}/scripts/common/utils.sh"

########################################
# Configuration
########################################

TRINO_NAMESPACE="${TRINO_NAMESPACE:-trino}"
SPARK_NAMESPACE="${SPARK_NAMESPACE:-spark}"

########################################
# Helper Functions
########################################

detect_query_engines() {
  local engines=()

  # Check for Trino
  if kubectl get namespace "${TRINO_NAMESPACE}" &>/dev/null && \
     kubectl get deployment trino -n "${TRINO_NAMESPACE}" &>/dev/null 2>&1; then
    engines+=("trino")
  fi

  # Check for Spark (future)
  if kubectl get namespace "${SPARK_NAMESPACE}" &>/dev/null && \
     kubectl get deployment spark -n "${SPARK_NAMESPACE}" &>/dev/null 2>&1; then
    engines+=("spark")
  fi

  echo "${engines[@]}"
}

show_usage() {
  cat << EOF
${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}
${YELLOW}WarpStream Tableflow Demo - Query Interface${NC}
${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}

Usage: ./demo-query.sh [QUERY_TYPE]

Query Types:
  time-travel    Query historical Iceberg snapshots (interactive)
  help           Show this help message

Examples:
  ./demo-query.sh time-travel    # Interactive time travel queries
  ./demo-query.sh                # Show interactive menu

${YELLOW}Note:${NC} Available query engines depend on your backend:
  - MinIO backend: Trino (supports time-travel)
  - Azure backend: Not yet supported (azblob:// URI incompatibility)

EOF
}

run_time_travel() {
  local engine="$1"

  case "$engine" in
    trino)
      echo -e "${GREEN}Launching Trino Time Travel Query Tool...${NC}"
      echo
      exec "${SCRIPT_DIR}/scripts/trino-time-travel.sh"
      ;;
    spark)
      echo -e "${GREEN}Launching Spark Time Travel Query Tool...${NC}"
      echo
      # Future: exec "${SCRIPT_DIR}/scripts/spark-time-travel.sh"
      echo -e "${YELLOW}Spark time travel queries coming soon!${NC}"
      exit 1
      ;;
    *)
      echo -e "${RED}Unknown query engine: ${engine}${NC}"
      exit 1
      ;;
  esac
}

interactive_menu() {
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}WarpStream Tableflow Demo - Query Interface${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo

  # Detect available engines
  local engines=($(detect_query_engines))

  if [ "${#engines[@]}" -eq 0 ]; then
    echo -e "${RED}No query engines detected!${NC}"
    echo
    echo "Please deploy a supported backend first:"
    echo "  export TABLEFLOW_BACKEND='minio'"
    echo "  ./demo-startup.sh"
    echo
    exit 1
  fi

  echo -e "${GREEN}Detected query engines:${NC}"
  for engine in "${engines[@]}"; do
    case "$engine" in
      trino)
        echo "  ✓ Trino (namespace: ${TRINO_NAMESPACE})"
        ;;
      spark)
        echo "  ✓ Spark (namespace: ${SPARK_NAMESPACE})"
        ;;
    esac
  done
  echo

  # Select engine if multiple available
  local selected_engine
  if [ "${#engines[@]}" -eq 1 ]; then
    selected_engine="${engines[0]}"
    echo -e "${GREEN}Using query engine: ${selected_engine}${NC}"
    echo
  else
    echo "Multiple query engines available. Select one:"
    for i in "${!engines[@]}"; do
      echo "  $((i+1))) ${engines[$i]}"
    done
    echo
    read -p "Select engine (1-${#engines[@]}): " engine_choice

    if ! [[ "$engine_choice" =~ ^[0-9]+$ ]] || [ "$engine_choice" -lt 1 ] || [ "$engine_choice" -gt "${#engines[@]}" ]; then
      echo -e "${RED}Invalid selection${NC}"
      exit 1
    fi

    selected_engine="${engines[$((engine_choice-1))]}"
    echo
  fi

  # Show available query types
  echo -e "${YELLOW}Available query types:${NC}"
  echo "  1) Time Travel - Query historical Iceberg snapshots"
  echo "  2) Exit"
  echo
  read -p "Select query type (1-2): " query_choice

  case "$query_choice" in
    1)
      echo
      run_time_travel "$selected_engine"
      ;;
    2)
      echo "Exiting."
      exit 0
      ;;
    *)
      echo -e "${RED}Invalid selection${NC}"
      exit 1
      ;;
  esac
}

########################################
# Main execution
########################################

require_cmd kubectl

# Parse command line arguments
if [ $# -eq 0 ]; then
  # No arguments - show interactive menu
  interactive_menu
else
  case "$1" in
    time-travel)
      # Detect engine and run time travel
      engines=($(detect_query_engines))

      if [ "${#engines[@]}" -eq 0 ]; then
        echo -e "${RED}No query engines detected!${NC}"
        echo "Please deploy the demo with MinIO backend first."
        exit 1
      fi

      # Use first available engine (prefer Trino)
      if [[ " ${engines[@]} " =~ " trino " ]]; then
        run_time_travel "trino"
      elif [[ " ${engines[@]} " =~ " spark " ]]; then
        run_time_travel "spark"
      else
        run_time_travel "${engines[0]}"
      fi
      ;;
    help|--help|-h)
      show_usage
      ;;
    *)
      echo -e "${RED}Unknown query type: $1${NC}"
      echo
      show_usage
      exit 1
      ;;
  esac
fi
