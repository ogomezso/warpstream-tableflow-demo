#!/bin/bash
# Azure authentication and subscription management

# DEPRECATED: This function is no longer used by the demo scripts.
# Users should manage their Azure authentication and subscription selection
# via 'az login' and 'az account set' before running the demo.
# Kept for backward compatibility only.
select_azure_subscription() {
  local preset_subscription="${AZURE_SUBSCRIPTION_ID:-}"
  if [ -n "$preset_subscription" ]; then
    if az account set --subscription "$preset_subscription" >/dev/null 2>&1; then
      return
    fi
    echo -e "${RED}Error: AZURE_SUBSCRIPTION_ID is set but invalid: ${preset_subscription}${NC}"
    exit 1
  fi

  local subscriptions
  subscriptions="$(az account list --query "[?state=='Enabled'].[id,name]" -o tsv)"

  if [ -z "$subscriptions" ]; then
    echo -e "${RED}Error: No enabled Azure subscriptions found for this account.${NC}"
    exit 1
  fi

  local count
  count="$(printf '%s\n' "$subscriptions" | wc -l | tr -d ' ')"

  if [ "$count" -eq 1 ]; then
    local only_id
    only_id="$(printf '%s\n' "$subscriptions" | awk -F '\t' '{print $1}')"
    az account set --subscription "$only_id" >/dev/null
    export AZURE_SUBSCRIPTION_ID="$only_id"
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Select Azure Subscription${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Multiple Azure subscriptions detected. Choose one:"
  echo
  local i=1
  while IFS=$'\t' read -r sub_id sub_name; do
    echo "  ${i}) ${sub_name} (${sub_id})"
    i=$((i + 1))
  done < <(echo "$subscriptions")
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1-${count}): " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
      break
    fi
    echo -e "${RED}Invalid choice. Please enter a number between 1 and ${count}.${NC}"
    choice=""
  done

  local selected_line
  selected_line="$(printf '%s\n' "$subscriptions" | sed -n "${choice}p")"
  local selected_id
  selected_id="$(printf '%s\n' "$selected_line" | awk -F '\t' '{print $1}')"

  az account set --subscription "$selected_id" >/dev/null
  export AZURE_SUBSCRIPTION_ID="$selected_id"
}

prompt_azure_resource_group() {
  # Check if already set
  if [ -n "${AZURE_RESOURCE_GROUP:-}" ] && [ -n "${AZURE_CREATE_RESOURCE_GROUP:-}" ]; then
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Azure Resource Group Configuration${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Choose resource group option:"
  echo
  echo "  1) Use existing resource group"
  echo "  2) Create new resource group"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1-2): " choice
    case "$choice" in
      1)
        export AZURE_CREATE_RESOURCE_GROUP="false"
        echo
        read -r -p "Enter existing resource group name: " AZURE_RESOURCE_GROUP
        while [ -z "$AZURE_RESOURCE_GROUP" ]; do
          echo -e "${RED}Resource group name cannot be empty.${NC}"
          read -r -p "Enter existing resource group name: " AZURE_RESOURCE_GROUP
        done

        # Verify resource group exists
        if ! az group show --name "$AZURE_RESOURCE_GROUP" >/dev/null 2>&1; then
          echo -e "${RED}Error: Resource group '$AZURE_RESOURCE_GROUP' not found in current subscription.${NC}"
          AZURE_RESOURCE_GROUP=""
          choice=""
          continue
        fi

        export AZURE_RESOURCE_GROUP
        echo -e "${GREEN}✓ Using existing resource group: ${AZURE_RESOURCE_GROUP}${NC}"
        break
        ;;
      2)
        export AZURE_CREATE_RESOURCE_GROUP="true"
        echo
        read -r -p "Enter new resource group name [warpstream-tableflow-demo]: " AZURE_RESOURCE_GROUP
        AZURE_RESOURCE_GROUP="${AZURE_RESOURCE_GROUP:-warpstream-tableflow-demo}"
        export AZURE_RESOURCE_GROUP

        echo
        read -r -p "Enter owner email (required by Azure policy): " AZURE_OWNER_EMAIL
        while [ -z "$AZURE_OWNER_EMAIL" ]; do
          echo -e "${RED}Owner email is required by Azure policy.${NC}"
          read -r -p "Enter owner email: " AZURE_OWNER_EMAIL
        done
        export AZURE_OWNER_EMAIL

        echo -e "${GREEN}✓ Will create resource group: ${AZURE_RESOURCE_GROUP}${NC}"
        echo -e "${GREEN}✓ Owner email: ${AZURE_OWNER_EMAIL}${NC}"
        break
        ;;
      *)
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        choice=""
        ;;
    esac
  done
}

prompt_azure_storage_account() {
  # Check if already set
  if [ -n "${AZURE_STORAGE_ACCOUNT:-}" ] && [ -n "${AZURE_CREATE_STORAGE_ACCOUNT:-}" ]; then
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Azure Storage Account Configuration${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Choose storage account option:"
  echo
  echo "  1) Use existing storage account"
  echo "  2) Create new storage account"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1-2): " choice
    case "$choice" in
      1)
        export AZURE_CREATE_STORAGE_ACCOUNT="false"
        echo
        read -r -p "Enter existing storage account name: " AZURE_STORAGE_ACCOUNT
        while [ -z "$AZURE_STORAGE_ACCOUNT" ]; do
          echo -e "${RED}Storage account name cannot be empty.${NC}"
          read -r -p "Enter existing storage account name: " AZURE_STORAGE_ACCOUNT
        done

        # Verify storage account exists
        if ! az storage account show --name "$AZURE_STORAGE_ACCOUNT" --resource-group "${AZURE_RESOURCE_GROUP}" >/dev/null 2>&1; then
          echo -e "${RED}Error: Storage account '$AZURE_STORAGE_ACCOUNT' not found in resource group '${AZURE_RESOURCE_GROUP}'.${NC}"
          AZURE_STORAGE_ACCOUNT=""
          choice=""
          continue
        fi

        export AZURE_STORAGE_ACCOUNT
        echo -e "${GREEN}✓ Using existing storage account: ${AZURE_STORAGE_ACCOUNT}${NC}"
        break
        ;;
      2)
        export AZURE_CREATE_STORAGE_ACCOUNT="true"
        echo
        read -r -p "Enter new storage account name [wstableflowdemo]: " AZURE_STORAGE_ACCOUNT
        AZURE_STORAGE_ACCOUNT="${AZURE_STORAGE_ACCOUNT:-wstableflowdemo}"
        export AZURE_STORAGE_ACCOUNT

        echo -e "${GREEN}✓ Will create storage account: ${AZURE_STORAGE_ACCOUNT}${NC}"
        break
        ;;
      *)
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        choice=""
        ;;
    esac
  done
}

prompt_azure_container() {
  # Check if already set
  if [ -n "${AZURE_CONTAINER:-}" ] && [ -n "${AZURE_CREATE_CONTAINER:-}" ]; then
    return
  fi

  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Azure Container Configuration${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "Choose container option:"
  echo
  echo "  1) Use existing container"
  echo "  2) Create new container"
  echo

  local choice=""
  while [ -z "$choice" ]; do
    read -r -p "Enter your choice (1-2): " choice
    case "$choice" in
      1)
        export AZURE_CREATE_CONTAINER="false"
        echo
        read -r -p "Enter existing container name: " AZURE_CONTAINER
        while [ -z "$AZURE_CONTAINER" ]; do
          echo -e "${RED}Container name cannot be empty.${NC}"
          read -r -p "Enter existing container name: " AZURE_CONTAINER
        done

        # Verify container exists
        local storage_account_key=$(az storage account keys list --resource-group "${AZURE_RESOURCE_GROUP}" --account-name "${AZURE_STORAGE_ACCOUNT}" --query '[0].value' -o tsv 2>/dev/null)
        if ! az storage fs show --name "$AZURE_CONTAINER" --account-name "${AZURE_STORAGE_ACCOUNT}" --account-key "$storage_account_key" >/dev/null 2>&1; then
          echo -e "${RED}Error: Container '$AZURE_CONTAINER' not found in storage account '${AZURE_STORAGE_ACCOUNT}'.${NC}"
          AZURE_CONTAINER=""
          choice=""
          continue
        fi

        export AZURE_CONTAINER
        echo -e "${GREEN}✓ Using existing container: ${AZURE_CONTAINER}${NC}"
        break
        ;;
      2)
        export AZURE_CREATE_CONTAINER="true"
        echo
        read -r -p "Enter new container name [tableflow]: " AZURE_CONTAINER
        AZURE_CONTAINER="${AZURE_CONTAINER:-tableflow}"
        export AZURE_CONTAINER

        echo -e "${GREEN}✓ Will create container: ${AZURE_CONTAINER}${NC}"
        break
        ;;
      *)
        echo -e "${RED}Invalid choice. Please enter 1 or 2.${NC}"
        choice=""
        ;;
    esac
  done
}

ensure_azure_login() {
  # Check if user is logged in and has an active subscription
  if ! az account show >/dev/null 2>&1; then
    echo
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${RED}Error: Azure CLI not authenticated${NC}"
    echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo
    echo "Please authenticate with Azure CLI and rerun this script:"
    echo
    echo -e "  ${CYAN}az login${NC}"
    echo
    echo "Optional: If you need to specify a tenant:"
    echo -e "  ${CYAN}az login --tenant YOUR_TENANT_ID${NC}"
    echo
    echo "After logging in, set your desired subscription:"
    echo -e "  ${CYAN}az account set --subscription YOUR_SUBSCRIPTION_ID${NC}"
    echo
    exit 1
  fi

  # Get current subscription info
  local subscription_name
  local subscription_id
  local tenant_id
  subscription_name="$(az account show --query name -o tsv 2>/dev/null || echo 'Unknown')"
  subscription_id="$(az account show --query id -o tsv 2>/dev/null || echo 'Unknown')"
  tenant_id="$(az account show --query tenantId -o tsv 2>/dev/null || echo '')"

  # Verify token is valid by attempting to list resource groups
  # This catches expired tokens that 'az account show' doesn't detect
  echo "Validating Azure token..."
  local token_check_output
  local token_check_error

  # Temporarily disable exit-on-error to capture the output properly
  # (script runs with set -e, so we need to handle errors manually here)
  set +e
  token_check_output=$(az group list --query '[0].name' -o tsv 2>&1)
  token_check_error=$?
  set -e

  # Debug output if DEBUG env var is set
  if [ "${DEBUG:-false}" = "true" ]; then
    echo "DEBUG: Token check exit code: $token_check_error"
    echo "DEBUG: Token check output: $token_check_output"
  fi

  if [ $token_check_error -ne 0 ]; then
    # Token validation failed - determine why
    echo ""  # Blank line for readability

    # Check if error is due to expired/invalid token
    if echo "$token_check_output" | grep -qi "AADSTS\|expired\|invalid.*token\|sign-in frequency\|refresh token"; then
      # Token expired or invalid
      printf "\n"
      printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
      printf "${RED}Error: Azure CLI token has expired${NC}\n"
      printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
      printf "\n"
      printf "Your Azure authentication token has expired or is invalid.\n"
      printf "This can happen due to:\n"
      printf "  - Token expiration (typically after 1-2 hours)\n"
      printf "  - Conditional access policies requiring re-authentication\n"
      printf "  - Security policies enforcing sign-in frequency\n"
      printf "\n"
      printf "Please re-authenticate and rerun this script:\n"
      printf "\n"

      if [ -n "$tenant_id" ]; then
        printf "  az logout\n"
        printf "  az login --tenant \"${tenant_id}\"\n"
      else
        printf "  az logout\n"
        printf "  az login\n"
      fi

      printf "\n"
      printf "After logging in, set your subscription:\n"
      printf "  az account set --subscription \"${subscription_id}\"\n"
      printf "\n"

      # Ensure output is flushed
      exec >&2
      exit 1
    else
      # Different error - might be permissions or network issue
      printf "\n"
      printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
      printf "${RED}Error: Unable to validate Azure credentials${NC}\n"
      printf "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
      printf "\n"
      printf "Failed to list resource groups. This might be due to:\n"
      printf "  - Insufficient permissions on the subscription\n"
      printf "  - Network connectivity issues\n"
      printf "  - Azure service outage\n"
      printf "\n"
      printf "Error details:\n"
      printf "%s\n" "$token_check_output"
      printf "\n"
      printf "Please verify:\n"
      printf "  1. You have at least Reader permissions on the subscription\n"
      printf "  2. Network connectivity to Azure\n"
      printf "  3. Try re-authenticating:\n"
      printf "\n"
      printf "     az logout\n"
      printf "     az login\n"
      printf "\n"

      # Ensure output is flushed
      exec >&2
      exit 1
    fi
  fi

  echo -e "${GREEN}✓ Azure CLI authenticated${NC}"
  echo -e "${GREEN}  Subscription: ${subscription_name}${NC}"
  echo -e "${GREEN}  ID: ${subscription_id}${NC}"

  # Export subscription ID for Terraform
  export AZURE_SUBSCRIPTION_ID="$subscription_id"
}
