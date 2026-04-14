#!/bin/bash

################################################################################
# Script: gcp.sh
# Description: GCP authentication and credential helpers
################################################################################

# Check if user is authenticated with GCP
is_gcp_authenticated() {
  if gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>/dev/null | grep -q .; then
    return 0
  else
    return 1
  fi
}

# DEPRECATED: This function is no longer used by the demo scripts.
# Users should manage their GCP authentication via 'gcloud auth application-default login'
# and project selection via 'gcloud config set project' before running the demo.
# Kept for backward compatibility only.
authenticate_gcp() {
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}GCP Authentication${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo

  # Check if already authenticated
  if is_gcp_authenticated; then
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    echo -e "${GREEN}✓ Already authenticated as: ${active_account}${NC}"

    # Get current project
    local current_project=$(gcloud config get-value project 2>/dev/null)
    if [ -n "$current_project" ]; then
      echo -e "${GREEN}✓ Current project: ${current_project}${NC}"
    fi

    return 0
  fi

  echo "Please authenticate with Google Cloud:"
  echo "  This will open a browser window for authentication"
  echo

  # Run gcloud auth login
  if ! gcloud auth login; then
    echo -e "${RED}GCP authentication failed${NC}"
    return 1
  fi

  # Verify authentication
  if is_gcp_authenticated; then
    local active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)")
    echo -e "${GREEN}✓ Authenticated as: ${active_account}${NC}"
    return 0
  else
    echo -e "${RED}GCP authentication verification failed${NC}"
    return 1
  fi
}

# DEPRECATED: This function is no longer used by the demo scripts.
# Users should manage their GCP project selection via 'gcloud config set project'
# before running the demo. Kept for backward compatibility only.
validate_gcp_project() {
  # Check if project is already set
  if [ -n "${GCP_PROJECT:-}" ]; then
    echo -e "${GREEN}Using pre-configured GCP project: ${GCP_PROJECT}${NC}"
    gcloud config set project "${GCP_PROJECT}" >/dev/null 2>&1
    return 0
  fi

  # Get current project
  local current_project=$(gcloud config get-value project 2>/dev/null)

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Select GCP Project${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo

  if [ -n "$current_project" ]; then
    echo -e "${CYAN}Current GCP project: ${current_project}${NC}"
    echo
    local use_current=""
    while [ -z "$use_current" ]; do
      read -r -p "Use this project? (yes/no): " use_current
      use_current=$(echo "$use_current" | tr '[:upper:]' '[:lower:]')

      case "$use_current" in
        yes|y)
          export GCP_PROJECT="$current_project"
          echo -e "${GREEN}✓ Using project: ${GCP_PROJECT}${NC}"
          echo
          return 0
          ;;
        no|n)
          break
          ;;
        *)
          echo -e "${RED}Please answer 'yes' or 'no'.${NC}"
          use_current=""
          ;;
      esac
    done
    echo
  fi

  # List available projects
  echo "Available GCP projects:"
  echo
  gcloud projects list --format="table(projectId,name,projectNumber)"
  echo

  # Prompt for project
  local project_id=""
  while [ -z "$project_id" ]; do
    read -r -p "Enter GCP project ID: " project_id

    if [ -z "$project_id" ]; then
      echo -e "${RED}Project ID cannot be empty${NC}"
      continue
    fi

    # Verify project exists
    if gcloud projects describe "$project_id" >/dev/null 2>&1; then
      export GCP_PROJECT="$project_id"
      gcloud config set project "$project_id" >/dev/null 2>&1
      echo -e "${GREEN}✓ Set project to: ${GCP_PROJECT}${NC}"
      echo
      return 0
    else
      echo -e "${RED}Project '${project_id}' not found or not accessible${NC}"
      project_id=""
    fi
  done
}

# Enable required GCP APIs
enable_gcp_apis() {
  echo
  echo -e "${CYAN}Enabling required GCP APIs...${NC}"

  local apis=(
    "storage-api.googleapis.com"
    "storage-component.googleapis.com"
  )

  for api in "${apis[@]}"; do
    echo "  Enabling ${api}..."
    if ! gcloud services enable "$api" --project="${GCP_PROJECT}" 2>/dev/null; then
      echo -e "${YELLOW}  Warning: Could not enable ${api} (might already be enabled)${NC}"
    fi
  done

  echo -e "${GREEN}✓ API check complete${NC}"
}

# Create service account for Terraform (optional)
create_terraform_service_account() {
  local sa_name="tableflow-demo-terraform"
  local sa_email="${sa_name}@${GCP_PROJECT}.iam.gserviceaccount.com"

  echo
  echo -e "${CYAN}Checking for Terraform service account...${NC}"

  # Check if service account exists
  if gcloud iam service-accounts describe "$sa_email" --project="${GCP_PROJECT}" >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Service account already exists: ${sa_email}${NC}"
  else
    echo "Creating service account for Terraform..."
    if ! gcloud iam service-accounts create "$sa_name" \
      --display-name="Tableflow Demo Terraform" \
      --project="${GCP_PROJECT}"; then
      echo -e "${YELLOW}Warning: Could not create service account${NC}"
      return 1
    fi

    echo -e "${GREEN}✓ Created service account: ${sa_email}${NC}"
  fi

  # Grant necessary roles
  echo "Granting roles to service account..."
  local roles=(
    "roles/storage.admin"
  )

  for role in "${roles[@]}"; do
    gcloud projects add-iam-policy-binding "${GCP_PROJECT}" \
      --member="serviceAccount:${sa_email}" \
      --role="$role" \
      --condition=None \
      >/dev/null 2>&1 || echo -e "${YELLOW}Warning: Could not grant ${role}${NC}"
  done

  echo -e "${GREEN}✓ Service account configured${NC}"
}

# Simplified GCP validation - no interactive prompts
# Users must authenticate and configure project beforehand
ensure_gcp_credentials() {
  # Check if application default credentials exist
  echo "Validating GCP credentials..."

  # Check if gcloud is configured with an active account
  local active_account
  set +e
  active_account=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" 2>&1)
  local auth_check=$?
  set -e

  if [ $auth_check -ne 0 ] || [ -z "$active_account" ]; then
    printf "\n"
    printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${RED}Error: GCP CLI not authenticated${NC}\n"
    printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "\n"
    printf "Please authenticate with Google Cloud and rerun this script:\n"
    printf "\n"
    printf "  ${CYAN}gcloud auth application-default login${NC}\n"
    printf "\n"
    printf "This sets up Application Default Credentials (ADC) for Terraform.\n"
    printf "\n"
    exit 1
  fi

  # Check if project is configured
  local current_project
  current_project=$(gcloud config get-value project 2>/dev/null || echo "")

  # Allow override via GCP_PROJECT or use GCP_PROJECT from environment
  if [ -n "${GCP_PROJECT:-}" ]; then
    current_project="$GCP_PROJECT"
    gcloud config set project "$GCP_PROJECT" >/dev/null 2>&1 || true
  fi

  if [ -z "$current_project" ]; then
    printf "\n"
    printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${RED}Error: GCP project not configured${NC}\n"
    printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "\n"
    printf "Please set your GCP project and rerun this script:\n"
    printf "\n"
    printf "  ${CYAN}gcloud config set project YOUR_PROJECT_ID${NC}\n"
    printf "\n"
    printf "Or set the GCP_PROJECT environment variable:\n"
    printf "\n"
    printf "  ${CYAN}export GCP_PROJECT=YOUR_PROJECT_ID${NC}\n"
    printf "  ${CYAN}./demo-startup.sh${NC}\n"
    printf "\n"
    printf "To list your projects:\n"
    printf "  ${CYAN}gcloud projects list${NC}\n"
    printf "\n"
    exit 1
  fi

  # Safety check: prevent using production project
  if [ "$current_project" = "claude-code-prod" ]; then
    printf "\n"
    printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${RED}Error: Cannot use production project${NC}\n"
    printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "\n"
    printf "The project '${current_project}' is a production project and cannot be used for demos.\n"
    printf "\n"
    printf "This is a safety measure to prevent accidental resource creation/deletion in production.\n"
    printf "\n"
    printf "Please switch to a development or demo project:\n"
    printf "\n"
    printf "  ${CYAN}gcloud config set project YOUR_DEV_PROJECT_ID${NC}\n"
    printf "\n"
    printf "To list your non-production projects:\n"
    printf "  ${CYAN}gcloud projects list --filter=\"-projectId:*-prod\"${NC}\n"
    printf "\n"
    exit 1
  fi

  # Validate credentials by attempting to access the project
  echo "Validating GCP access to project..."
  local project_check
  set +e
  project_check=$(gcloud projects describe "$current_project" --format="value(projectId)" 2>&1)
  local project_error=$?
  set -e

  if [ $project_error -ne 0 ]; then
    printf "\n"
    printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "${RED}Error: Cannot access GCP project${NC}\n"
    printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    printf "\n"
    printf "Failed to access project: ${current_project}\n"
    printf "\n"
    printf "This might be due to:\n"
    printf "  - Project does not exist\n"
    printf "  - Insufficient permissions\n"
    printf "  - Invalid project ID\n"
    printf "  - Expired credentials\n"
    printf "\n"
    printf "Error details:\n"
    printf "%s\n" "$project_check"
    printf "\n"
    printf "Please verify:\n"
    printf "  1. Project ID is correct: ${CYAN}gcloud projects list${NC}\n"
    printf "  2. You have access to the project\n"
    printf "  3. Re-authenticate if needed: ${CYAN}gcloud auth application-default login${NC}\n"
    printf "\n"
    exit 1
  fi

  # Get project details
  local project_name
  local project_number
  project_name=$(gcloud projects describe "$current_project" --format="value(name)" 2>/dev/null || echo "Unknown")
  project_number=$(gcloud projects describe "$current_project" --format="value(projectNumber)" 2>/dev/null || echo "Unknown")

  printf "${GREEN}✓ GCP credentials validated${NC}\n"
  printf "${GREEN}  Account: ${active_account}${NC}\n"
  printf "${GREEN}  Project: ${project_name}${NC}\n"
  printf "${GREEN}  Project ID: ${current_project}${NC}\n"

  # Export for Terraform
  export GCP_PROJECT="$current_project"

  # Enable required APIs
  enable_gcp_apis

  # Get or set GCP region - always use TABLEFLOW_REGION if set
  if [ -n "${TABLEFLOW_REGION:-}" ]; then
    export GCP_REGION="${TABLEFLOW_REGION}"
    echo -e "${GREEN}✓ Using GCP region: ${GCP_REGION} (from TABLEFLOW_REGION)${NC}"
  elif [ -z "${GCP_REGION:-}" ]; then
    # Try to get from gcloud config
    GCP_REGION=$(gcloud config get-value compute/region 2>/dev/null || echo "")
    if [ -z "${GCP_REGION}" ]; then
      # Default to us-central1 if not set
      GCP_REGION="us-central1"
      echo -e "${YELLOW}GCP region not configured, defaulting to: ${GCP_REGION}${NC}"
    fi
    export GCP_REGION
    echo -e "${GREEN}✓ Using GCP region: ${GCP_REGION}${NC}"
  else
    # GCP_REGION is already set
    echo -e "${GREEN}✓ Using GCP region: ${GCP_REGION}${NC}"
  fi
}

# DEPRECATED: Old function kept for backward compatibility
# Use ensure_gcp_credentials() instead
validate_gcp_credentials() {
  ensure_gcp_credentials
}

# Get default GCP region for Terraform
get_gcp_region() {
  echo "${GCP_REGION:-${TABLEFLOW_REGION:-us-central1}}"
}

# Get GCP project for Terraform
get_gcp_project() {
  echo "${GCP_PROJECT}"
}

# Prompt for GCS bucket (existing or new)
prompt_gcp_bucket() {
  # Check if already set
  if [ -n "${GCP_BUCKET_NAME:-}" ] && [ -n "${GCP_CREATE_BUCKET:-}" ]; then
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}GCP GCS Bucket Configuration${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Choose GCS bucket option:"
  echo
  echo "  1) Use existing GCS bucket"
  echo "  2) Create new GCS bucket"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1-2): " choice
    case "$choice" in
      1)
        export GCP_CREATE_BUCKET="false"
        echo
        read -r -p "Enter existing GCS bucket name: " GCP_BUCKET_NAME
        while [ -z "$GCP_BUCKET_NAME" ]; do
          echo -e "${RED}Bucket name cannot be empty.${NC}"
          read -r -p "Enter existing GCS bucket name: " GCP_BUCKET_NAME
        done

        # Verify bucket exists
        if ! gsutil ls -b "gs://$GCP_BUCKET_NAME" >/dev/null 2>&1; then
          echo -e "${RED}Error: GCS bucket '$GCP_BUCKET_NAME' not found or not accessible.${NC}"
          GCP_BUCKET_NAME=""
          choice=""
          continue
        fi

        export GCP_BUCKET_NAME
        echo -e "${GREEN}✓ Using existing GCS bucket: ${GCP_BUCKET_NAME}${NC}"
        break
        ;;
      2)
        export GCP_CREATE_BUCKET="true"
        echo
        read -r -p "Enter new GCS bucket name [warpstream-tableflow-demo-$(date +%s)]: " GCP_BUCKET_NAME
        GCP_BUCKET_NAME="${GCP_BUCKET_NAME:-warpstream-tableflow-demo-$(date +%s)}"
        export GCP_BUCKET_NAME

        echo -e "${GREEN}✓ Will create GCS bucket: ${GCP_BUCKET_NAME}${NC}"
        break
        ;;
      *)
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        choice=""
        ;;
    esac
  done
}
