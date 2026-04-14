#!/bin/bash
# WarpStream environment validation functions

# Source colors if not already loaded
if [ -z "${GREEN:-}" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "${SCRIPT_DIR}/colors.sh"
fi

prompt_warpstream_api_key() {
  # Check if already set
  if [ -n "${WARPSTREAM_DEPLOY_API_KEY:-}" ]; then
    echo -e "${GREEN}✓ WarpStream API key is already set${NC}"

    # Validate it's not a key ID (should be the actual key)
    if [[ "${WARPSTREAM_DEPLOY_API_KEY}" == aki_* ]]; then
      echo -e "${RED}Error: WARPSTREAM_DEPLOY_API_KEY looks like a key ID (starts with 'aki_').${NC}"
      echo -e "${YELLOW}Please provide the actual API key value (starts with 'aks_').${NC}"
      unset WARPSTREAM_DEPLOY_API_KEY
    else
      return 0
    fi
  fi

  # Display information banner
  echo
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}WarpStream API Key Required${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo
  echo "This demo requires a WarpStream account API key to:"
  echo "  • Create and manage WarpStream virtual clusters"
  echo "  • Generate agent keys for the WarpStream agents"
  echo "  • Configure Tableflow pipelines"
  echo
  echo -e "${CYAN}How to get your API key:${NC}"
  echo -e "  1. Sign up or log in at: ${GREEN}https://console.warpstream.com/${NC}"
  echo -e "  2. Navigate to Settings → API Keys"
  echo -e "  3. Create a new API key or copy an existing one"
  echo -e "  4. The key should start with 'aks_' (all API keys use this prefix)"
  echo
  echo -e "${YELLOW}Note:${NC} Do NOT use a key ID (starting with 'aki_')"
  echo

  # Prompt for the key (hidden input)
  while [ -z "${WARPSTREAM_DEPLOY_API_KEY:-}" ]; do
    read -r -s -p "Enter your WarpStream account API key: " WARPSTREAM_DEPLOY_API_KEY
    echo  # New line after hidden input

    if [ -z "${WARPSTREAM_DEPLOY_API_KEY}" ]; then
      echo -e "${RED}API key cannot be empty${NC}"
      continue
    fi

    # Validate it's not a key ID (should be the actual key)
    if [[ "${WARPSTREAM_DEPLOY_API_KEY}" == aki_* ]]; then
      echo -e "${RED}Error: This looks like a key ID (starts with 'aki_').${NC}"
      echo -e "${YELLOW}Please provide the actual API key value (starts with 'aks_').${NC}"
      WARPSTREAM_DEPLOY_API_KEY=""
      continue
    fi
  done

  export WARPSTREAM_DEPLOY_API_KEY
  echo -e "${GREEN}✓ WarpStream API key configured${NC}"
  echo
}

ensure_required_env_vars() {
  if [ -z "${WARPSTREAM_DEPLOY_API_KEY:-}" ]; then
    prompt_warpstream_api_key
  else
    # Validate if already set
    while [[ "${WARPSTREAM_DEPLOY_API_KEY}" == aki_* ]]; do
      echo -e "${RED}Error: WARPSTREAM_DEPLOY_API_KEY looks like a key ID (starts with 'aki_').${NC}"
      echo -e "${YELLOW}Please provide the actual API key value (starts with 'aks_').${NC}"
      unset WARPSTREAM_DEPLOY_API_KEY
      prompt_warpstream_api_key
    done
  fi

  if [ -n "${WARPSTREAM_AGENT_KEY_OVERRIDE:-}" ]; then
    if [[ "${WARPSTREAM_AGENT_KEY_OVERRIDE}" != aks_* ]]; then
      echo -e "${RED}Error: WARPSTREAM_AGENT_KEY must be an agent key starting with 'aks_'.${NC}"
      exit 1
    fi

    if [ "${WARPSTREAM_AGENT_KEY_OVERRIDE}" = "${WARPSTREAM_DEPLOY_API_KEY}" ]; then
      echo -e "${RED}Error: WARPSTREAM_AGENT_KEY must be different from WARPSTREAM_DEPLOY_API_KEY.${NC}"
      exit 1
    fi
  fi
}
