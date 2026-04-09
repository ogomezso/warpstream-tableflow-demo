#!/bin/bash
# Common utility functions

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo -e "${RED}Error: Required command not found: $1${NC}"
    exit 1
  fi
}

validate_paths() {
  local path="$1"
  if [ ! -e "$path" ]; then
    echo -e "${RED}Error: Required path not found: $path${NC}"
    exit 1
  fi
}

prompt_for_env_var() {
  local var_name="$1"
  local prompt_text="$2"
  local secret_input="${3:-false}"
  local value=""

  while [ -z "$value" ]; do
    if [ "$secret_input" = "true" ]; then
      read -r -s -p "$prompt_text" value
      echo
    else
      read -r -p "$prompt_text" value
    fi

    if [ -z "$value" ]; then
      echo -e "${YELLOW}Value cannot be empty. Please try again.${NC}"
    fi
  done

  export "$var_name=$value"
}

is_debug_enabled() {
  case "${DEBUG:-false}" in
    true|TRUE|1|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

debug_log() {
  if is_debug_enabled; then
    echo -e "${YELLOW}[DEBUG] $*${NC}"
  fi
}

prompt_tableflow_backend() {
  # Check if backend is already set via environment variable
  if [ -n "${TABLEFLOW_BACKEND:-}" ]; then
    echo -e "${GREEN}Using pre-configured Tableflow backend: ${TABLEFLOW_BACKEND}${NC}"
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Select Tableflow Backend Storage${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Choose the object storage backend for WarpStream Tableflow:"
  echo
  echo "  1) Azure ADLS Gen2 (Azure Data Lake Storage Gen2)"
  echo "     - Cloud-based storage"
  echo "     - Requires Azure subscription and credentials"
  echo "     - Production-ready"
  echo
  echo "  2) MinIO (S3-compatible)"
  echo "     - Kubernetes-based storage"
  echo "     - No cloud credentials required"
  echo "     - Great for development and testing"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1 or 2): " choice

    case "$choice" in
      1)
        export TABLEFLOW_BACKEND="azure"
        echo -e "${GREEN}✓ Selected: Azure ADLS Gen2${NC}"
        ;;
      2)
        export TABLEFLOW_BACKEND="minio"
        echo -e "${GREEN}✓ Selected: MinIO${NC}"
        ;;
      *)
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        choice=""
        ;;
    esac
  done

  echo
}
