#!/bin/bash

################################################################################
# Script: aws.sh
# Description: AWS authentication and credential helpers
################################################################################

# Check if user is authenticated with AWS
is_aws_authenticated() {
  if aws sts get-caller-identity >/dev/null 2>&1; then
    return 0
  else
    return 1
  fi
}

# Prompt user if they are a Confluent employee
prompt_confluent_employee() {
  if [ -n "${CONFLUENT_EMPLOYEE:-}" ]; then
    echo -e "${GREEN}Using pre-configured Confluent employee status: ${CONFLUENT_EMPLOYEE}${NC}"
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}AWS Authentication${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Are you a Confluent employee?"
  echo
  echo "  • YES: Use AWS SSO with assume role (recommended for Confluent employees)"
  echo "  • NO:  Use standard AWS CLI authentication"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Are you a Confluent employee? (yes/no): " choice
    local choice_lower=$(echo "$choice" | tr '[:upper:]' '[:lower:]')

    case "$choice_lower" in
      yes|y)
        export CONFLUENT_EMPLOYEE="true"
        echo -e "${GREEN}✓ Using Confluent employee authentication (AWS SSO + assume role)${NC}"
        ;;
      no|n)
        export CONFLUENT_EMPLOYEE="false"
        echo -e "${GREEN}✓ Using standard AWS CLI authentication${NC}"
        ;;
      *)
        echo -e "${RED}Please answer 'yes' or 'no'.${NC}"
        choice=""
        ;;
    esac
  done

  echo
}

# Authenticate as Confluent employee (Using Granted 'assume -ex' command)
authenticate_aws_confluent_employee() {
  echo -e "${CYAN}Authenticating with AWS (Confluent employee)...${NC}"
  echo

  # Check if granted is installed
  if ! command -v granted >/dev/null 2>&1; then
    echo -e "${RED}Error: 'granted' CLI not found${NC}"
    echo "Please install Granted CLI: https://docs.commonfate.io/granted/getting-started"
    echo "Then run: granted registry add -n confluent -u git@github.com:confluentinc/granted-registry.git"
    return 1
  fi

  # Check if already authenticated
  if is_aws_authenticated; then
    local identity=$(aws sts get-caller-identity --output json 2>/dev/null)
    if [ $? -eq 0 ]; then
      local user_arn=$(echo "$identity" | jq -r '.Arn')
      local account=$(echo "$identity" | jq -r '.Account')
      echo -e "${GREEN}✓ Already authenticated as: ${user_arn}${NC}"
      echo -e "${GREEN}✓ AWS Account: ${account}${NC}"

      # Check if credentials are already exported
      if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        echo -e "${GREEN}✓ AWS credentials already exported${NC}"

        read -r -p "Do you want to switch to a different AWS profile? (y/n): " switch_profile
        switch_profile=$(echo "$switch_profile" | tr '[:upper:]' '[:lower:]')
        if [[ "$switch_profile" != "y" && "$switch_profile" != "yes" ]]; then
          return 0
        fi
        echo
      else
        # Authenticated but credentials not in env vars - need to export them
        echo -e "${YELLOW}Credentials not in environment variables, re-running assume to export them...${NC}"
        # Fall through to run granted assume -ex
      fi
    fi
  fi

  echo "Running 'assume -ex' to select AWS profile..."
  echo "This will show an interactive menu of available Confluent AWS profiles."
  echo

  # Use granted assume with -ex flag for interactive profile selection
  # The -ex flag outputs export statements that can be eval'd
  local temp_exports=$(mktemp)

  # Run granted assume -ex interactively (let it use the TTY directly)
  granted assume -ex > "$temp_exports"
  local assume_rc=$?

  # Debug: show what was captured (only in debug mode)
  if is_debug_enabled && [ -s "$temp_exports" ]; then
    echo -e "${CYAN}DEBUG: Captured export statements:${NC}"
    grep "^export" "$temp_exports" || echo "  (no export statements found)"
  fi

  if [ $assume_rc -ne 0 ] || [ ! -s "$temp_exports" ]; then
    # If granted assume fails or produces no output, try alternative methods
    echo -e "${YELLOW}Granted assume didn't produce export statements${NC}"

    if is_aws_authenticated; then
      echo -e "${YELLOW}Attempting to export credentials from active AWS session...${NC}"

      # Try to get credentials using AWS CLI
      local aws_creds=$(aws configure export-credentials --format env 2>/dev/null || true)
      if [ -n "$aws_creds" ]; then
        eval "$aws_creds"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
        export AWS_SESSION_TOKEN
        rm -f "$temp_exports"
        echo -e "${GREEN}✓ Exported credentials from AWS session${NC}"
      else
        echo -e "${RED}Failed to export credentials from AWS session${NC}"
        echo -e "${YELLOW}Your AWS session may be using a credential process or profile that doesn't support direct credential export.${NC}"
        echo -e "${YELLOW}The Trino deployment requires explicit AWS credentials in environment variables.${NC}"
        rm -f "$temp_exports"
        return 1
      fi
    else
      echo -e "${RED}Failed to run 'granted assume -ex' (exit code: $assume_rc)${NC}"
      rm -f "$temp_exports"
      return 1
    fi
  else
    # Eval the export statements to load credentials into current shell
    while IFS= read -r line; do
      if [[ "$line" =~ ^export ]]; then
        eval "$line"
      fi
    done < "$temp_exports"
    rm -f "$temp_exports"
  fi

  # Verify authentication
  echo
  if is_aws_authenticated; then
    local identity=$(aws sts get-caller-identity --output json)
    local user_arn=$(echo "$identity" | jq -r '.Arn')
    local account=$(echo "$identity" | jq -r '.Account')
    echo -e "${GREEN}✓ Authenticated as: ${user_arn}${NC}"
    echo -e "${GREEN}✓ AWS Account: ${account}${NC}"

    # Ensure credentials are exported
    export AWS_ACCESS_KEY_ID
    export AWS_SECRET_ACCESS_KEY
    export AWS_SESSION_TOKEN

    # Verify credentials are actually in environment
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
      echo -e "${GREEN}✓ AWS credentials exported to environment${NC}"
    else
      echo -e "${YELLOW}Warning: Credentials not in environment variables${NC}"
      echo -e "${YELLOW}Attempting to retrieve from AWS session...${NC}"

      # Try to get credentials from AWS CLI
      local aws_creds=$(aws configure export-credentials --format env 2>/dev/null || true)
      if [ -n "$aws_creds" ]; then
        eval "$aws_creds"
        export AWS_ACCESS_KEY_ID
        export AWS_SECRET_ACCESS_KEY
        export AWS_SESSION_TOKEN
        echo -e "${GREEN}✓ Credentials retrieved from AWS session${NC}"
      else
        echo -e "${RED}Failed to retrieve credentials${NC}"
        return 1
      fi
    fi

    return 0
  else
    echo -e "${RED}AWS authentication verification failed${NC}"
    echo "Credentials may not have been properly exported."
    echo
    echo "Note: The 'assume' command is a shell function. If this fails, please run:"
    echo -e "${YELLOW}  assume -ex${NC}"
    echo "in your shell, then re-run this script."
    return 1
  fi
}

# Authenticate with standard AWS CLI
authenticate_aws_standard() {
  echo -e "${CYAN}Authenticating with AWS CLI...${NC}"

  # Check if already authenticated
  if is_aws_authenticated; then
    local identity=$(aws sts get-caller-identity --output json)
    local user_arn=$(echo "$identity" | jq -r '.Arn')
    local account=$(echo "$identity" | jq -r '.Account')
    echo -e "${GREEN}✓ Already authenticated as: ${user_arn}${NC}"
    echo -e "${GREEN}✓ AWS Account: ${account}${NC}"
    return 0
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}AWS CLI Configuration Required${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Please authenticate with AWS CLI:"
  echo "  1. Run: aws configure"
  echo "  2. Enter your AWS Access Key ID"
  echo "  3. Enter your AWS Secret Access Key"
  echo "  4. Enter default region (e.g., us-east-1)"
  echo

  read -r -p "Press Enter once you've completed AWS configuration..."
  echo

  # Verify authentication
  if is_aws_authenticated; then
    local identity=$(aws sts get-caller-identity --output json)
    local user_arn=$(echo "$identity" | jq -r '.Arn')
    local account=$(echo "$identity" | jq -r '.Account')
    echo -e "${GREEN}✓ Authenticated as: ${user_arn}${NC}"
    echo -e "${GREEN}✓ AWS Account: ${account}${NC}"
    return 0
  else
    echo -e "${RED}AWS authentication failed. Please run 'aws configure' and try again.${NC}"
    return 1
  fi
}

# Main AWS authentication function
validate_aws_credentials() {
  prompt_confluent_employee

  if [ "${CONFLUENT_EMPLOYEE}" = "true" ]; then
    authenticate_aws_confluent_employee
  else
    authenticate_aws_standard
  fi

  if [ $? -ne 0 ]; then
    echo -e "${RED}Failed to authenticate with AWS${NC}"
    exit 1
  fi

  # Ensure credentials are exported for child processes
  export AWS_ACCESS_KEY_ID
  export AWS_SECRET_ACCESS_KEY
  export AWS_SESSION_TOKEN

  # Get or set AWS region - always use TABLEFLOW_REGION if set
  if [ -n "${TABLEFLOW_REGION:-}" ]; then
    export AWS_REGION="${TABLEFLOW_REGION}"
    export AWS_DEFAULT_REGION="${TABLEFLOW_REGION}"
    echo -e "${GREEN}✓ Using AWS region: ${AWS_REGION} (from TABLEFLOW_REGION)${NC}"
  elif [ -z "${AWS_REGION:-}" ]; then
    # Try to get from AWS config
    AWS_REGION=$(aws configure get region 2>/dev/null || echo "")
    if [ -z "${AWS_REGION}" ]; then
      echo
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo -e "${YELLOW}AWS Region Required${NC}"
      echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
      echo
      echo "AWS region not configured in your AWS CLI."
      echo
      while [ -z "${AWS_REGION}" ]; do
        read -r -p "Enter AWS region (e.g., us-east-1): " AWS_REGION
        if [ -z "${AWS_REGION}" ]; then
          echo -e "${RED}Region cannot be empty${NC}"
        fi
      done
      echo -e "${GREEN}✓ AWS region set to: ${AWS_REGION}${NC}"
      echo
    fi
    export AWS_REGION
    export AWS_DEFAULT_REGION="${AWS_REGION}"
    echo -e "${GREEN}✓ Using AWS region: ${AWS_REGION}${NC}"
  else
    # AWS_REGION is already set, ensure AWS_DEFAULT_REGION matches
    export AWS_DEFAULT_REGION="${AWS_REGION}"
    echo -e "${GREEN}✓ Using AWS region: ${AWS_REGION} (already set)${NC}"
  fi
}

# Get default AWS region for Terraform
get_aws_region() {
  echo "${AWS_REGION:-${TABLEFLOW_REGION:-us-east-1}}"
}

# Prompt for S3 bucket (existing or new)
prompt_aws_bucket() {
  # Check if already set
  if [ -n "${AWS_BUCKET_NAME:-}" ] && [ -n "${AWS_CREATE_BUCKET:-}" ]; then
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}AWS S3 Bucket Configuration${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Choose S3 bucket option:"
  echo
  echo "  1) Use existing S3 bucket"
  echo "  2) Create new S3 bucket"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1-2): " choice
    case "$choice" in
      1)
        export AWS_CREATE_BUCKET="false"
        echo
        read -r -p "Enter existing S3 bucket name: " AWS_BUCKET_NAME
        while [ -z "$AWS_BUCKET_NAME" ]; do
          echo -e "${RED}Bucket name cannot be empty.${NC}"
          read -r -p "Enter existing S3 bucket name: " AWS_BUCKET_NAME
        done

        # Verify bucket exists
        if ! aws s3api head-bucket --bucket "$AWS_BUCKET_NAME" 2>/dev/null; then
          echo -e "${RED}Error: S3 bucket '$AWS_BUCKET_NAME' not found or not accessible.${NC}"
          AWS_BUCKET_NAME=""
          choice=""
          continue
        fi

        export AWS_BUCKET_NAME
        echo -e "${GREEN}✓ Using existing S3 bucket: ${AWS_BUCKET_NAME}${NC}"
        break
        ;;
      2)
        export AWS_CREATE_BUCKET="true"
        echo
        read -r -p "Enter new S3 bucket name [warpstream-tableflow-demo-$(date +%s)]: " AWS_BUCKET_NAME
        AWS_BUCKET_NAME="${AWS_BUCKET_NAME:-warpstream-tableflow-demo-$(date +%s)}"
        export AWS_BUCKET_NAME

        echo -e "${GREEN}✓ Will create S3 bucket: ${AWS_BUCKET_NAME}${NC}"
        break
        ;;
      *)
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        choice=""
        ;;
    esac
  done
}
