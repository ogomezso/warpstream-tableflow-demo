#!/bin/bash
# WarpStream environment validation functions

ensure_required_env_vars() {
  if [ -z "${WARPSTREAM_DEPLOY_API_KEY:-}" ]; then
    echo -e "${YELLOW}Required environment variable WARPSTREAM_DEPLOY_API_KEY is not set.${NC}"
    prompt_for_env_var "WARPSTREAM_DEPLOY_API_KEY" "Enter WARPSTREAM_DEPLOY_API_KEY (account API key): " "true"
  fi

  while [[ "${WARPSTREAM_DEPLOY_API_KEY}" == aki_* ]]; do
    echo -e "${RED}Error: WARPSTREAM_DEPLOY_API_KEY looks like an agent key (starts with 'aki_').${NC}"
    echo -e "${YELLOW}Please provide a WarpStream account API key/token for Terraform provider auth.${NC}"
    prompt_for_env_var "WARPSTREAM_DEPLOY_API_KEY" "Enter WARPSTREAM_DEPLOY_API_KEY (account API key): " "true"
  done

  if [ -n "${WARPSTREAM_AGENT_KEY_OVERRIDE:-}" ]; then
    if [[ "${WARPSTREAM_AGENT_KEY_OVERRIDE}" != aki_* ]]; then
      echo -e "${RED}Error: WARPSTREAM_AGENT_KEY must be an agent key starting with 'aki_'.${NC}"
      exit 1
    fi

    if [ "${WARPSTREAM_AGENT_KEY_OVERRIDE}" = "${WARPSTREAM_DEPLOY_API_KEY}" ]; then
      echo -e "${RED}Error: WARPSTREAM_AGENT_KEY must be different from WARPSTREAM_DEPLOY_API_KEY.${NC}"
      exit 1
    fi
  fi
}
