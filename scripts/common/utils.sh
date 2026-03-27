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
