# Demo Startup Modules

This folder contains the modular components used by `demo-startup.sh` to deploy the WarpStream Tableflow demo environment.

## Overview

The startup process is divided into 6 sequential steps, each implemented as a separate module. The main script (`demo-startup.sh`) sources these modules and executes them in order.

## Module Execution Order

| Step | Module | Description |
|------|--------|-------------|
| 1/6 | `01-cfk.sh` | Install CFK (Confluent for Kubernetes) operator if not present |
| 2/6 | `02-confluent.sh` | Deploy Confluent Platform resources (Kafka, Schema Registry, Connect, Control Center) |
| 3/6 | `03-datagen.sh` | Deploy datagen source connector for generating sample order data |
| 4/6 | `04-terraform.sh` | Apply Azure and WarpStream Terraform resources |
| 5/6 | `05-warpstream-agent.sh` | Render and deploy WarpStream agent with Azure credentials |
| 6/6 | `06-tableflow-pipeline.sh` | Create Tableflow pipeline to stream orders to Azure Blob Storage |

## Module Details

### 01-cfk.sh
- Checks if CFK operator is already installed
- Installs via Helm if not present
- Waits for operator deployment rollout

### 02-confluent.sh
- Creates Confluent namespace
- Applies Confluent Platform CRs
- Waits for all pods to be ready

### 03-datagen.sh
- Deploys datagen connector CR
- Creates `datagen-orders` topic

### 04-terraform.sh
- Ensures Azure CLI authentication
- Validates WarpStream API key
- Applies Azure storage resources
- Applies WarpStream cluster resources

### 05-warpstream-agent.sh
- Retrieves Terraform outputs (storage account, agent key, etc.)
- Renders agent configuration from template
- Deploys agent via Helm

### 06-tableflow-pipeline.sh
- Generates pipeline YAML from template
- Applies Tableflow pipeline via Terraform

## Shared Dependencies

All modules depend on common utilities from `scripts/common/`:
- `colors.sh` - Terminal color definitions
- `utils.sh` - General utility functions
- `azure.sh` - Azure authentication helpers
- `terraform.sh` - Terraform operations
- `warpstream.sh` - WarpStream env validation
- `kubernetes.sh` - Kubernetes helpers

## Usage

These modules are not meant to be executed directly. They are sourced by `demo-startup.sh`:

```bash
./demo-startup.sh
```

## Adding New Steps

To add a new step:
1. Create a new module file following the naming convention `NN-name.sh`
2. Implement a `run_step_<name>()` function
3. Source the module in `demo-startup.sh`
4. Call the step function in the appropriate order
