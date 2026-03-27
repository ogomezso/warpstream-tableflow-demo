# Demo Cleanup Modules

This folder contains the modular components used by `demo-cleanup.sh` to tear down the WarpStream Tableflow demo environment.

## Overview

The cleanup process is divided into 6 sequential steps, each implemented as a separate module. The main script (`demo-cleanup.sh`) sources these modules and executes them in reverse order of creation to properly handle dependencies.

## Module Execution Order

| Step | Module | Description |
|------|--------|-------------|
| 1/6 | `01-credentials.sh` | Validate Azure and WarpStream credentials |
| 2/6 | `02-tableflow-pipeline.sh` | Destroy Tableflow pipeline via Terraform |
| 3/6 | `03-warpstream-k8s.sh` | Remove WarpStream Kubernetes resources (Helm, secrets, namespace) |
| 4/6 | `04-terraform.sh` | Destroy WarpStream and Azure Terraform resources |
| 5/6 | `05-confluent.sh` | Delete Confluent resources, namespaces, and optionally CFK operator |
| 6/6 | `06-cleanup-files.sh` | Remove generated files and Terraform state |

## Module Details

### 01-credentials.sh
- Ensures Azure CLI is authenticated
- Validates WarpStream deploy API key

### 02-tableflow-pipeline.sh
- Destroys Tableflow pipeline via Terraform
- Tracks success for conditional state cleanup

### 03-warpstream-k8s.sh
- Uninstalls WarpStream Helm release
- Removes agent secrets
- Deletes WarpStream namespace

### 04-terraform.sh
- Destroys WarpStream cluster resources
- Destroys Azure storage resources
- Tracks success flags for each

### 05-confluent.sh
- Deletes datagen connector
- Deletes Confluent Platform CRs
- Removes Confluent namespace
- Optionally uninstalls CFK operator

### 06-cleanup-files.sh
- Removes generated agent config and backups
- Removes generated pipeline config
- Cleans Terraform state (only if destroy was successful)

## Error Handling

The cleanup process continues even if individual steps fail:
- Failures are recorded and reported at the end
- Pending namespace deletions are tracked
- Terraform state is preserved if destroy fails

## Shared Dependencies

All modules depend on common utilities from `scripts/common/`:
- `colors.sh` - Terminal color definitions
- `utils.sh` - General utility functions
- `azure.sh` - Azure authentication helpers
- `terraform.sh` - Terraform operations
- `warpstream.sh` - WarpStream env validation
- `kubernetes.sh` - Kubernetes helpers (namespace deletion, failure tracking)

## Usage

These modules are not meant to be executed directly. They are sourced by `demo-cleanup.sh`:

```bash
./demo-cleanup.sh
```

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CLEANUP_REMOVE_CFK_OPERATOR` | `true` | Set to `false` to keep CFK operator installed |
| `NAMESPACE_DELETE_TIMEOUT_SECONDS` | `30` | Timeout for namespace deletion |

## Adding New Steps

To add a new cleanup step:
1. Create a new module file following the naming convention `NN-name.sh`
2. Implement a `run_step_<name>()` function
3. Source the module in `demo-cleanup.sh`
4. Call the step function in the appropriate order
