# Common Modules

This folder contains shared utility functions used by both `demo-startup.sh` and `demo-cleanup.sh`.

## Modules

| Module | Description |
|--------|-------------|
| `colors.sh` | Terminal color definitions (RED, GREEN, YELLOW, NC) |
| `utils.sh` | General utilities: command validation, path validation, env prompting, debug logging |
| `azure.sh` | Azure CLI authentication and subscription selection |
| `terraform.sh` | Terraform apply, output, and destroy operations |
| `warpstream.sh` | WarpStream API key validation |
| `kubernetes.sh` | Kubernetes helpers: namespace deletion, failure tracking |

## Module Details

### colors.sh
Defines ANSI color codes for terminal output:
- `RED` - Error messages
- `GREEN` - Success messages
- `YELLOW` - Warnings and progress
- `NC` - Reset (no color)

### utils.sh
- `require_cmd` - Verify a command exists
- `validate_paths` - Verify a path exists
- `prompt_for_env_var` - Interactive prompt for missing env vars
- `is_debug_enabled` - Check DEBUG flag
- `debug_log` - Output debug messages when enabled

### azure.sh
- `ensure_azure_login` - Handle Azure CLI auth (including expired tokens)
- `select_azure_subscription` - Interactive subscription selection

### terraform.sh
- `terraform_apply_if_needed` - Apply only when changes detected
- `terraform_output_raw` - Get raw output value
- `terraform_destroy_if_exists` - Safe destroy with success tracking

### warpstream.sh
- `ensure_required_env_vars` - Validate WARPSTREAM_DEPLOY_API_KEY and agent key formats

### kubernetes.sh
- `wait_for_namespace_deletion` - Poll namespace until deleted
- `record_failure` - Track failures for final report
- `record_pending_namespace` - Track namespaces still terminating

## Usage

These modules are sourced at the beginning of the main scripts:

```bash
source "${SCRIPT_DIR}/scripts/common/colors.sh"
source "${SCRIPT_DIR}/scripts/common/utils.sh"
# ... etc
```

## Dependencies

Modules may depend on each other:
- Most modules require `colors.sh` for output formatting
- `azure.sh` requires `utils.sh` for `prompt_for_env_var`
- `terraform.sh` requires `kubernetes.sh` for `record_failure`

Always source `colors.sh` and `utils.sh` first.
