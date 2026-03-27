#!/bin/bash
# Azure authentication and subscription management

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

  echo -e "${YELLOW}Multiple Azure subscriptions detected. Choose one:${NC}"
  local i=1
  while IFS=$'\t' read -r sub_id sub_name; do
    echo "  ${i}) ${sub_name} (${sub_id})"
    i=$((i + 1))
  done <<< "$subscriptions"

  local choice=""
  while :; do
    read -r -p "Enter subscription number [1-${count}]: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$count" ]; then
      break
    fi
    echo -e "${YELLOW}Invalid selection. Please enter a number between 1 and ${count}.${NC}"
  done

  local selected_line
  selected_line="$(printf '%s\n' "$subscriptions" | sed -n "${choice}p")"
  local selected_id
  selected_id="$(printf '%s\n' "$selected_line" | awk -F '\t' '{print $1}')"

  az account set --subscription "$selected_id" >/dev/null
  export AZURE_SUBSCRIPTION_ID="$selected_id"
}

ensure_azure_login() {
  local needs_login=false

  if ! az account show >/dev/null 2>&1; then
    needs_login=true
  else
    if ! az account list >/dev/null 2>&1; then
      echo -e "${YELLOW}Azure token appears expired. Re-authenticating...${NC}"
      needs_login=true
    fi
  fi

  if [ "$needs_login" = true ]; then
    echo -e "${YELLOW}Azure CLI authentication required. Logging out and re-authenticating...${NC}"
    az logout >/dev/null 2>&1 || true

    local login_cmd="az login"
    if [ -n "${AZURE_TENANT_ID:-}" ]; then
      login_cmd="$login_cmd --tenant \"$AZURE_TENANT_ID\""
    fi
    if [ -n "${AZURE_LOGIN_SCOPE:-}" ]; then
      login_cmd="$login_cmd --scope \"$AZURE_LOGIN_SCOPE\""
    fi

    eval "$login_cmd"

    if ! az account show >/dev/null 2>&1; then
      echo -e "${RED}Error: Azure login failed. Run 'az login' and retry.${NC}"
      exit 1
    fi
  else
    echo -e "${GREEN}✓ Azure CLI already authenticated${NC}"
  fi

  select_azure_subscription

  local account_name
  account_name="$(az account show --query name -o tsv 2>/dev/null || true)"
  echo -e "${GREEN}✓ Azure subscription selected${NC}${account_name:+ (${account_name})}"
}
