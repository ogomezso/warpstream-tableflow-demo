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

prompt_cloud_provider() {
  # Check if provider is already set via environment variable
  if [ -n "${CLOUD_PROVIDER:-}" ]; then
    echo -e "${GREEN}Using pre-configured cloud provider: ${CLOUD_PROVIDER}${NC}"
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Select Cloud Provider${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Choose where to deploy your WarpStream Tableflow cluster:"
  echo
  echo "  1) AWS (Amazon Web Services)"
  echo "     - S3 storage backend"
  echo "     - Trino query engine supported"
  echo
  echo "  2) Azure (Microsoft Azure)"
  echo "     - ADLS Gen2 storage backend"
  echo "     - Trino query engine supported"
  echo
  echo "  3) GCP (Google Cloud Platform)"
  echo "     - Google Cloud Storage (GCS) backend"
  echo "     - Trino query engine supported"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1-3): " choice

    case "$choice" in
      1)
        export CLOUD_PROVIDER="aws"
        echo -e "${GREEN}✓ Selected: AWS${NC}"
        ;;
      2)
        export CLOUD_PROVIDER="azure"
        echo -e "${GREEN}✓ Selected: Azure${NC}"
        ;;
      3)
        export CLOUD_PROVIDER="gcp"
        echo -e "${GREEN}✓ Selected: GCP${NC}"
        ;;
      *)
        echo -e "${RED}Invalid choice. Please enter 1, 2, or 3.${NC}"
        choice=""
        ;;
    esac
  done

  echo
}

prompt_region() {
  local provider="$1"

  # Check if region is already set
  if [ -n "${TABLEFLOW_REGION:-}" ]; then
    echo -e "${GREEN}Using pre-configured region: ${TABLEFLOW_REGION}${NC}"
    return
  fi

  # Source regions
  source "${SCRIPT_DIR}/scripts/common/regions.sh"

  local provider_upper=$(echo "$provider" | tr '[:lower:]' '[:upper:]')

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Select Region for ${provider_upper}${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Available regions:"
  echo

  # Get regions for provider
  local regions=()
  while IFS= read -r region; do
    regions+=("$region")
  done < <(get_regions_for_provider "$provider")

  # Display numbered list
  local i=1
  for region in "${regions[@]}"; do
    local description=$(get_region_description "$provider" "$region")
    printf "  %2d) %-20s %s\n" "$i" "$region" "($description)"
    ((i++))
  done

  echo
  local default_region=$(get_default_region "$provider")
  echo -e "${CYAN}Default: $default_region${NC}"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1-${#regions[@]}) or press Enter for default: " choice

    # Use default if empty
    if [ -z "$choice" ]; then
      export TABLEFLOW_REGION="$default_region"
      echo -e "${GREEN}✓ Selected: $default_region (default)${NC}"
      break
    fi

    # Validate choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#regions[@]}" ]; then
      local selected_region="${regions[$((choice-1))]}"
      export TABLEFLOW_REGION="$selected_region"
      echo -e "${GREEN}✓ Selected: $selected_region${NC}"
    else
      echo -e "${RED}Invalid choice. Please enter a number between 1 and ${#regions[@]}.${NC}"
      choice=""
    fi
  done

  echo
}

prompt_tableflow_backend() {
  local provider="$1"

  # Check if backend is already set via environment variable
  if [ -n "${TABLEFLOW_BACKEND:-}" ]; then
    echo -e "${GREEN}Using pre-configured backend: ${TABLEFLOW_BACKEND}${NC}"
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Select Storage Backend${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Choose the storage backend for your Tableflow cluster:"
  echo

  case "$provider" in
    aws)
      echo "  1) AWS S3 (Cloud Storage)"
      echo "     - Native AWS S3 bucket in same region as cluster"
      echo "     - Trino query engine supported"
      echo "     - Production-ready"
      ;;
    azure)
      echo "  1) Azure ADLS Gen2 (Cloud Storage)"
      echo "     - Azure Data Lake Storage Gen2 in same region"
      echo "     - Trino query engine supported (ABFSS protocol)"
      echo "     - Production-ready"
      ;;
    gcp)
      echo "  1) Google Cloud Storage (GCS)"
      echo "     - GCS bucket in same region as cluster"
      echo "     - Trino query engine supported"
      echo "     - Production-ready"
      ;;
  esac

  echo
  echo "  2) MinIO (Local Kubernetes Storage)"
  echo "     - S3-compatible storage running in Kubernetes"
  echo "     - No cloud credentials required"
  echo "     - Trino query engine supported"
  echo "     - Great for development and testing"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1 or 2): " choice

    case "$choice" in
      1)
        export TABLEFLOW_BACKEND="cloud"
        echo -e "${GREEN}✓ Selected: Cloud-native storage${NC}"
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
