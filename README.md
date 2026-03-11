# WarpStream Tableflow Demo

This demo deploys a complete environment for WarpStream Tableflow integration with Confluent Platform on Kubernetes, using Azure Blob Storage as the backing store.

## Architecture

```text
┌─────────────────────────────────────────────────────────────────┐
│                      Kubernetes Cluster                         │
│                                                                 │
│  ┌─────────────────────────────┐  ┌──────────────────────────┐  │
│  │   Confluent Platform (CFK)  │  │   WarpStream Namespace   │  │
│  │                             │  │                          │  │
│  │  - KRaft Controller         │  │  - WarpStream Agent      │  │
│  │  - Kafka Broker             │  │  - Azure Credentials     │  │
│  │  - Schema Registry          │  │                          │  │
│  │  - Kafka Connect (datagen)  │  └──────────┬───────────────┘  │
│  │  - Control Center Next-Gen  │             │                  │
│  └─────────────────────────────┘             │                  │
└──────────────────────────────────────────────┼──────────────────┘
                                               │
                    ┌──────────────────────────┴──────────────────────────┐
                    │                                                     │
          ┌─────────▼─────────┐                           ┌───────────────▼───────────────┐
          │  WarpStream Cloud │                           │       Azure Storage           │
          │                   │                           │                               │
          │  - Tableflow      │                           │  - Storage Account            │
          │    Cluster        │◄─────────────────────────►│  - Blob Container (tableflow) │
          │  - Agent Key      │                           │                               │
          └───────────────────┘                           └───────────────────────────────┘
```

## Prerequisites

### Required CLI Tools

- `kubectl` - Kubernetes CLI with cluster access configured
- `helm` - Helm package manager (v3+)
- `terraform` - Terraform CLI
- `az` - Azure CLI

### Accounts & Access

- **Kubernetes cluster** - Access to a running Kubernetes cluster
- **WarpStream account** - Account API key for Terraform provider authentication
- **Azure subscription** - Active Azure subscription with permissions to create storage resources

## Environment Variables

### Required

| Variable | Description |
|----------|-------------|
| `WARPSTREAM_DEPLOY_API_KEY` | WarpStream account API key for Terraform provider authentication. Must NOT start with `aki_` (that's an agent key). |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `WARPSTREAM_AGENT_KEY` | (from Terraform) | Override for the WarpStream agent key. Must start with `aki_`. |
| `AZURE_SUBSCRIPTION_ID` | (interactive) | Azure subscription ID. If not set, you'll be prompted to select one. |
| `TABLEFLOW_REGION` | `eastus` | Azure region for the WarpStream Tableflow cluster. |
| `CONFLUENT_NAMESPACE` | `confluent` | Kubernetes namespace for Confluent Platform resources. |
| `WARPSTREAM_NAMESPACE` | `warpstream` | Kubernetes namespace for WarpStream resources. |
| `CFK_NAMESPACE` | `confluent` | Kubernetes namespace for CFK operator. |
| `CFK_RELEASE` | `confluent-operator` | Helm release name for CFK operator. |
| `WARPSTREAM_HELM_RELEASE` | `warpstream-agent` | Helm release name for WarpStream agent. |
| `DEBUG` | `false` | Enable debug logging (`true`, `1`, `yes`, `on`). |

## Infrastructure Created

### Azure Resources (Terraform)

| Resource | Name | Description |
|----------|------|-------------|
| Storage Account | `wsdemostore` | Azure Storage Account with LRS replication |
| Blob Container | `tableflow` | Private container for WarpStream data |

Location: `environment/azure/main.tf`

### WarpStream Resources (Terraform)

| Resource | Name | Description |
|----------|------|-------------|
| Tableflow Cluster | `vcn_dl_tableflow_cluster_dev` | Dev-tier Tableflow cluster in Azure eastus |
| Agent Key | `akn_tableflow_demo_agent_key` | Agent key for WarpStream agent authentication |

Location: `environment/warpstream/cluster/main.tf`

### Kubernetes Resources

#### Confluent Platform (via CFK)

| Component | Replicas | Description |
|-----------|----------|-------------|
| KRaft Controller | 1 | Kafka metadata controller (replaces ZooKeeper) |
| Kafka Broker | 1 | Kafka broker with telemetry enabled |
| Schema Registry | 1 | Avro/JSON/Protobuf schema management |
| Kafka Connect | 1 | Connect cluster with datagen plugin |
| Control Center NG | 1 | Next-gen Confluent Control Center |

Location: `environment/confluent-platform/cp.yaml`

#### WarpStream

| Component | Description |
|-----------|-------------|
| WarpStream Agent | Agent deployment connecting to Tableflow cluster |
| Service Account | `warpstream-agent` |
| Secret | `azure-storage-credentials` - Azure storage access key |

Location: `environment/warpstream/warpstream-agent-template.yaml`

## Usage

### Running the Demo

```bash
# Set required environment variable
export WARPSTREAM_DEPLOY_API_KEY='your_warpstream_account_api_key'

# Optionally set Azure subscription
export AZURE_SUBSCRIPTION_ID='your_azure_subscription_id'

# Run the demo
./run_demo.sh
```

### What the Script Does

1. **CFK Operator Installation** - Installs Confluent for Kubernetes operator if not present
2. **Confluent Platform Deployment** - Deploys Kafka, Schema Registry, Connect, and Control Center
3. **Terraform Resources** - Provisions Azure storage and WarpStream Tableflow cluster
4. **WarpStream Agent Deployment** - Renders agent configuration and deploys via Helm

### Verifying the Deployment

```bash
# Check Confluent Platform pods
kubectl get pods -n confluent

# Check WarpStream agent
kubectl get pods -n warpstream

# View Control Center (port-forward)
kubectl port-forward svc/controlcenter-ng 9021:9021 -n confluent
```

## Cleanup

### Running Cleanup

```bash
# Set required environment variable
export WARPSTREAM_DEPLOY_API_KEY='your_warpstream_account_api_key'

# Run cleanup
./demo_clean-up.sh
```

### What Gets Removed

1. **WarpStream Kubernetes Resources** - Helm release, secrets, and namespace
2. **WarpStream Terraform Resources** - Tableflow cluster and agent key
3. **Azure Terraform Resources** - Storage account and container
4. **Confluent Resources** - Confluent Platform CRs, namespace, and CFK operator
5. **Generated Files** - Rendered manifests, Terraform state, and lock files

**Note:** If a namespace is still terminating after the timeout, the cleanup continues and reports a warning at the end with instructions to verify the namespace is fully deleted.

### Cleanup Options

| Variable | Default | Description |
|----------|---------|-------------|
| `CLEANUP_REMOVE_CFK_OPERATOR` | `true` | Set to `false` to keep the CFK operator installed |
| `NAMESPACE_DELETE_TIMEOUT_SECONDS` | `30` | Timeout for namespace deletion |

## Project Structure

```text
warpstream-tableflow-demo/
├── .gitignore                         # Git ignore (Terraform state, secrets)
├── README.md                          # This file
├── run_demo.sh                        # Main demo setup script
├── demo_clean-up.sh                   # Cleanup script
└── environment/
    ├── azure/
    │   └── main.tf                    # Azure storage resources
    ├── confluent-platform/
    │   └── cp.yaml                    # Confluent Platform CRs
    └── warpstream/
        ├── cluster/
        │   └── main.tf                # WarpStream Tableflow cluster
        ├── warpstream-agent-template.yaml  # Agent Helm values template
        └── warpstream-agent.yaml      # Generated agent config (created by run_demo.sh)
```

## Troubleshooting

### Azure Authentication Issues

```bash
# Re-authenticate with Azure
az login

# List available subscriptions
az account list --output table

# Set specific subscription
az account set --subscription "<subscription-id>"
```

### WarpStream Agent Key Issues

If you see errors about the agent key format:

```bash
# Check Terraform state
terraform -chdir=environment/warpstream/cluster state list

# Inspect agent key resource
terraform -chdir=environment/warpstream/cluster state show warpstream_agent_key.demo_agent_key

# Manually override agent key if needed
export WARPSTREAM_AGENT_KEY='aks_your_agent_key'
```

### Namespace Stuck in Terminating

If a namespace is stuck in `Terminating` state:

```bash
# Check for remaining resources
kubectl get all -n <namespace>

# Force delete if needed (use with caution)
kubectl delete namespace <namespace> --force --grace-period=0
```
