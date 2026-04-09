# WarpStream Tableflow Backend Options

This demo now supports two backend storage options for WarpStream Tableflow: **Azure ADLS Gen2** (cloud-based) and **MinIO** (Kubernetes-based).

## Quick Comparison

| Feature | Azure ADLS Gen2 | MinIO |
|---------|----------------|-------|
| **Deployment Location** | Azure Cloud | Kubernetes Cluster |
| **Cloud Credentials** | Required | Not Required |
| **Setup Complexity** | Moderate (Azure subscription) | Simple (kubectl only) |
| **Best For** | Production, cloud deployments | Development, testing, demos |
| **Cost** | Pay-per-use (Azure storage) | Free (uses cluster resources) |
| **Scalability** | Highly scalable | Limited by cluster resources |
| **Data Persistence** | Highly durable | Depends on K8s storage class |
| **External Access** | Via Azure portal/CLI | Via port-forward or ingress |

## Azure ADLS Gen2 Backend

### Overview
Azure Data Lake Storage Gen2 (ADLS Gen2) is Microsoft's cloud-based object storage solution, optimized for big data analytics workloads.

### Prerequisites
- Azure subscription
- Azure CLI installed and configured
- Terraform for resource provisioning
- `WARPSTREAM_DEPLOY_API_KEY` environment variable

### What Gets Deployed
- **Azure Storage Account** - `wsdemostore` (ADLS Gen2-enabled)
- **ADLS Gen2 Filesystem** - `tableflow` container
- **WarpStream Cluster** - Tableflow cluster configured for Azure
- **WarpStream Agent** - Configured with Azure credentials

### Usage

```bash
# Set environment variables
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'
export AZURE_SUBSCRIPTION_ID='your_subscription_id'  # Optional
export TABLEFLOW_BACKEND='azure'

# Run demo
./demo-startup.sh
```

### Configuration Details

The WarpStream agent is configured with:
- **Bucket URL**: `azblob://tableflow`
- **Authentication**: Azure Storage Account access key
- **Environment Variables**:
  - `AZURE_STORAGE_ACCOUNT`: Storage account name
  - `AZURE_STORAGE_KEY`: Access key (from Kubernetes secret)

### Verifying Data

```bash
# List files in ADLS Gen2
az storage fs file list \
  --account-name wsdemostore \
  --file-system tableflow \
  --path "warpstream/_tableflow/" \
  --output table

# Download a file
az storage fs file download \
  --account-name wsdemostore \
  --file-system tableflow \
  --path "path/to/file" \
  --file local-file
```

### Pros
- ✅ Production-ready and highly scalable
- ✅ Built-in data durability and redundancy
- ✅ Native Azure integration
- ✅ Pay-per-use pricing model
- ✅ Integrated with Azure security and compliance

### Cons
- ❌ Requires Azure subscription and credentials
- ❌ May incur cloud storage costs
- ❌ More complex setup than MinIO
- ❌ Requires internet connectivity

## MinIO Backend

### Overview
MinIO is an open-source, S3-compatible object storage server that runs entirely within your Kubernetes cluster. Perfect for development, testing, and demos.

### Prerequisites
- Kubernetes cluster with kubectl access
- Helm 3+
- Terraform for WarpStream cluster provisioning
- `WARPSTREAM_DEPLOY_API_KEY` environment variable
- **No cloud credentials required!**

### What Gets Deployed
- **MinIO Server** - S3-compatible object storage in Kubernetes
- **PersistentVolumeClaim** - 10Gi storage for data
- **MinIO Service** - ClusterIP service (API + Console)
- **MinIO Init Job** - Automatically creates `tableflow` bucket
- **WarpStream Cluster** - Tableflow cluster configured for S3
- **WarpStream Agent** - Configured with MinIO credentials

### Usage

```bash
# Set environment variable
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'
export TABLEFLOW_BACKEND='minio'

# Run demo
./demo-startup.sh
```

### Configuration Details

The WarpStream agent is configured with:
- **Bucket URL**: `"s3://tableflow?region=us-east-1&s3ForcePathStyle=true&endpoint=http://minio.minio.svc.cluster.local:9000"`
  - Must be quoted in YAML due to special characters
  - `region`: Required by WarpStream Tableflow
  - `s3ForcePathStyle=true`: Forces path-style access (required for MinIO)
  - `endpoint`: MinIO service endpoint in Kubernetes
- **Authentication**: MinIO access key and secret key
- **Environment Variables**:
  - `AWS_ACCESS_KEY_ID`: `minioadmin`
  - `AWS_SECRET_ACCESS_KEY`: `minioadmin` (from Kubernetes secret)
  - `WARPSTREAM_AVAILABILITY_ZONE`: `local-k8s-cluster` (required for local deployments where auto-detection fails)

### Accessing MinIO

#### MinIO Console (Web UI)
```bash
# Port-forward to access web console
kubectl port-forward -n minio svc/minio 9001:9001

# Open browser to http://localhost:9001
# Login: minioadmin / minioadmin
```

#### MinIO CLI (mc)
```bash
# Install MinIO client
brew install minio/stable/mc  # macOS

# Port-forward to API
kubectl port-forward -n minio svc/minio 9000:9000 &

# Configure alias
mc alias set local http://localhost:9000 minioadmin minioadmin

# List buckets
mc ls local

# Browse tableflow bucket
mc ls local/tableflow/warpstream/_tableflow/

# Download a file
mc cp local/tableflow/path/to/file ./local-file
```

### Verifying Data

```bash
# Via MinIO CLI
mc ls local/tableflow/warpstream/_tableflow/

# Via kubectl (for pod inspection)
kubectl exec -n minio deployment/minio -- \
  ls -la /data/tableflow/

# Via MinIO Console
# 1. Port-forward: kubectl port-forward -n minio svc/minio 9001:9001
# 2. Open: http://localhost:9001
# 3. Browse the tableflow bucket
```

### Pros
- ✅ No cloud credentials or subscription required
- ✅ Fast and easy setup
- ✅ Perfect for development and testing
- ✅ No cloud costs - uses cluster resources
- ✅ Works offline / air-gapped environments
- ✅ S3-compatible API (widely supported)
- ✅ Built-in web console for easy data inspection

### Cons
- ❌ Not recommended for production use
- ❌ Limited by cluster storage capacity
- ❌ Data persistence depends on K8s storage class
- ❌ Less scalable than cloud solutions
- ❌ Requires cluster resources (CPU, memory, storage)

## Switching Between Backends

### Changing Backend After Initial Setup

To switch from one backend to another:

```bash
# 1. Clean up existing deployment
./demo-cleanup.sh

# 2. Set the new backend
export TABLEFLOW_BACKEND='minio'  # or 'azure'

# 3. Run the demo again
./demo-startup.sh
```

### Running Both Backends Simultaneously

It's technically possible to run both backends simultaneously (they use separate namespaces and resources), but it's not recommended as:
- The WarpStream agent can only connect to one backend at a time
- You would need multiple WarpStream Tableflow clusters
- Resource usage would be doubled

## Architecture Differences

### Azure ADLS Gen2 Architecture
```
┌─────────────────────────┐
│  Kubernetes Cluster     │
│                         │
│  ┌──────────────────┐   │         ┌─────────────────┐
│  │ WarpStream Agent │───┼────────►│  Azure Cloud    │
│  │                  │   │         │                 │
│  │ - Azure creds    │   │         │  ADLS Gen2      │
│  └──────────────────┘   │         │  Storage Acct   │
│                         │         │  tableflow      │
└─────────────────────────┘         └─────────────────┘
```

### MinIO Architecture
```
┌─────────────────────────────────────────┐
│  Kubernetes Cluster                     │
│                                         │
│  ┌──────────────────┐   ┌───────────┐  │
│  │ WarpStream Agent │──►│   MinIO   │  │
│  │                  │   │           │  │
│  │ - MinIO creds    │   │ - Server  │  │
│  │                  │   │ - PVC     │  │
│  └──────────────────┘   │ - Bucket  │  │
│                         └───────────┘  │
└─────────────────────────────────────────┘
```

## Environment Variables Reference

### Common Variables (Both Backends)
```bash
WARPSTREAM_DEPLOY_API_KEY       # Required: WarpStream account API key
TABLEFLOW_BACKEND               # Optional: 'azure' or 'minio' (interactive if not set)
TABLEFLOW_REGION                # Optional: WarpStream region (default: eastus)
WARPSTREAM_NAMESPACE            # Optional: WarpStream K8s namespace (default: warpstream)
```

### Azure-Specific Variables
```bash
AZURE_SUBSCRIPTION_ID           # Optional: Azure subscription (interactive if not set)
AZURE_TENANT_ID                 # Optional: Azure tenant ID
AZURE_LOGIN_SCOPE               # Optional: Azure login scope
```

### MinIO-Specific Variables
```bash
MINIO_NAMESPACE                 # Optional: MinIO K8s namespace (default: minio)
# Note: MinIO credentials are hardcoded as minioadmin/minioadmin
```

## Troubleshooting

### Azure Backend Issues

#### Authentication Failures
```bash
# Re-authenticate with Azure
az logout
az login

# Verify subscription
az account list --output table
az account set --subscription "<subscription-id>"
```

#### Terraform Errors
```bash
# Check Terraform state
terraform -chdir=environment/azure state list

# Manually destroy and recreate
terraform -chdir=environment/azure destroy
terraform -chdir=environment/azure apply
```

### MinIO Backend Issues

#### MinIO Pod Not Starting
```bash
# Check pod status
kubectl get pods -n minio
kubectl describe pod -n minio -l app=minio

# Check PVC status
kubectl get pvc -n minio

# View logs
kubectl logs -n minio deployment/minio
```

#### Bucket Not Created
```bash
# Check init job
kubectl get jobs -n minio
kubectl logs -n minio job/minio-init

# Manually create bucket
kubectl port-forward -n minio svc/minio 9000:9000 &
mc alias set local http://localhost:9000 minioadmin minioadmin
mc mb local/tableflow
```

#### Cannot Connect to MinIO
```bash
# Verify MinIO is running
kubectl get pods -n minio
kubectl get svc -n minio

# Test connectivity from WarpStream pod
kubectl exec -n warpstream deployment/warpstream-agent -- \
  curl -v http://minio.minio.svc.cluster.local:9000/minio/health/live
```

### Common Issues (Both Backends)

#### WarpStream Agent Won't Start
```bash
# Check agent logs
kubectl logs -n warpstream deployment/warpstream-agent

# Verify configuration
kubectl get secret -n warpstream
kubectl describe deployment -n warpstream warpstream-agent

# Check backend connectivity
# For Azure:
kubectl exec -n warpstream deployment/warpstream-agent -- \
  env | grep AZURE

# For MinIO:
kubectl exec -n warpstream deployment/warpstream-agent -- \
  env | grep AWS
```

## Best Practices

### For Development/Testing
- ✅ Use **MinIO backend** for fast iteration
- ✅ No cloud costs or credential management
- ✅ Easy data inspection via web console
- ✅ Can run completely offline

### For Production
- ✅ Use **Azure ADLS Gen2 backend**
- ✅ Proper access control and security
- ✅ Data durability and compliance
- ✅ Scalability and performance
- ✅ Integration with Azure monitoring

### For Demos/Workshops
- ✅ **MinIO** for quick setup and no prerequisites
- ✅ **Azure** to showcase production architecture
- ✅ Consider audience: developers vs. architects

## Additional Resources

- [MinIO Documentation](https://min.io/docs/)
- [MinIO Kubernetes Guide](https://min.io/docs/minio/kubernetes/upstream/)
- [Azure ADLS Gen2 Documentation](https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction)
- [WarpStream Tableflow Documentation](https://docs.warpstream.com/)
- [MinIO Console Guide](https://min.io/docs/minio/linux/administration/minio-console.html)
