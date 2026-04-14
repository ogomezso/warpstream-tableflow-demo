# WarpStream Tableflow Backend Options

This demo supports **four backend storage options** for WarpStream Tableflow: **AWS S3**, **Azure ADLS Gen2**, **GCP Cloud Storage**, and **MinIO** (local S3-compatible storage).

## Quick Comparison

| Feature | AWS S3 | Azure ADLS Gen2 | GCP Cloud Storage | MinIO |
|---------|--------|-----------------|-------------------|-------|
| **Deployment Location** | AWS Cloud | Azure Cloud | GCP Cloud | Kubernetes Cluster |
| **Cloud Provider** | Amazon Web Services | Microsoft Azure | Google Cloud | Any (local) |
| **Cloud Credentials** | Required (IAM) | Required (Az CLI) | Required (Service Acct) | Not Required |
| **Trino Support** | ✅ Native S3 | ❌ No (azblob://) | ✅ Native GCS | ✅ S3A |
| **Setup Complexity** | Moderate | Moderate | Moderate | Simple |
| **Best For** | Production (AWS) | Production (Azure) | Production (GCP) | Development, demos |
| **Cost** | Pay-per-use | Pay-per-use | Pay-per-use | Free (cluster resources) |
| **Scalability** | Highly scalable | Highly scalable | Highly scalable | Limited by cluster |
| **Data Persistence** | Highly durable | Highly durable | Highly durable | Depends on K8s |
| **External Access** | AWS Console/CLI | Azure Portal/CLI | GCP Console/gsutil | Port-forward/ingress |

## AWS S3 Backend

### Overview
AWS S3 (Simple Storage Service) is Amazon's cloud object storage solution, widely used for data lakes and analytics workloads.

### Prerequisites
- AWS account with appropriate IAM permissions
- AWS CLI installed and configured
- Terraform for resource provisioning
- `WARPSTREAM_DEPLOY_API_KEY` environment variable
- **For Confluent employees:** AWS SSO access + assume role
- **For others:** Standard AWS CLI credentials

### What Gets Deployed
- **S3 Bucket** - With versioning and encryption
- **WarpStream Cluster** - Tableflow cluster configured for AWS region
- **WarpStream Agent** - Configured with AWS credentials (IAM or session token)
- **Trino Query Engine** - With native S3 filesystem support

### Usage

```bash
# Set environment variables
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'
export CLOUD_PROVIDER='aws'
export TABLEFLOW_REGION='us-east-1'  # or your preferred region
export TABLEFLOW_BACKEND='cloud'

# Run demo
./demo-startup.sh
```

### Authentication

**For Confluent Employees:**
```bash
# The script will detect and prompt
# Uses AWS SSO + assume role flow
aws sso login --profile your-profile
```

**For Non-Confluent Users:**
```bash
# Standard AWS CLI authentication
aws configure
# Enter: Access Key ID, Secret Access Key, Region, Output format
```

### Configuration Details

The WarpStream agent is configured with:
- **Bucket URL**: `s3://warpstream-tableflow-demo-<random-suffix>`
- **Authentication**: AWS credentials (access key, secret key, session token)
- **Environment Variables**:
  - `AWS_ACCESS_KEY_ID`: From AWS credentials
  - `AWS_SECRET_ACCESS_KEY`: From AWS credentials
  - `AWS_SESSION_TOKEN`: For temporary credentials (from Kubernetes secret)
  - `AWS_REGION`: Deployment region

**Trino Configuration:**
- Native S3 filesystem enabled (`fs.native-s3.enabled=true`)
- Direct S3 access without Hadoop
- Region-specific S3 endpoint
- Credentials from Kubernetes secret

### Verifying Data

```bash
# List files in S3
aws s3 ls s3://warpstream-tableflow-demo-<suffix>/warpstream/_tableflow/ --recursive

# Download a file
aws s3 cp s3://warpstream-tableflow-demo-<suffix>/path/to/file ./local-file

# View bucket details
aws s3api get-bucket-location --bucket warpstream-tableflow-demo-<suffix>
```

### Query with Trino

```bash
# Show tables
kubectl exec -n trino deployment/trino -- trino --execute \
  'SHOW TABLES FROM iceberg.default'

# Query orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'
```

### Pros
- ✅ Production-ready and highly scalable
- ✅ **Native Trino S3 support** - optimal performance
- ✅ Integrated AWS security and IAM
- ✅ Global availability with regional deployment
- ✅ Mature ecosystem and tooling
- ✅ Strong consistency guarantees

### Cons
- ❌ Requires AWS account and credentials
- ❌ Cloud storage costs (though cost-effective)
- ❌ Different authentication for Confluent employees

## GCP Cloud Storage Backend

### Overview
Google Cloud Storage (GCS) is Google's cloud object storage solution, optimized for analytics and machine learning workloads.

### Prerequisites
- GCP project with Storage API enabled
- gcloud CLI installed and configured
- Terraform for resource provisioning
- `WARPSTREAM_DEPLOY_API_KEY` environment variable
- Service account with Storage Admin role

### What Gets Deployed
- **GCS Bucket** - With versioning and uniform access
- **Service Account** - For Terraform and WarpStream agent
- **WarpStream Cluster** - Tableflow cluster configured for GCP region
- **WarpStream Agent** - Configured with service account credentials
- **Trino Query Engine** - With native GCS filesystem support

### Usage

```bash
# Set environment variables
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'
export CLOUD_PROVIDER='gcp'
export TABLEFLOW_REGION='us-central1'  # or your preferred region
export TABLEFLOW_BACKEND='cloud'

# Run demo
./demo-startup.sh
```

### Authentication

```bash
# Authenticate with gcloud
gcloud auth login
gcloud auth application-default login

# Select or create project
gcloud projects list
export GCP_PROJECT='your-project-id'
```

The script automatically:
1. Enables required APIs (Storage, IAM)
2. Creates service account for Terraform
3. Grants necessary permissions
4. Generates and stores service account key

### Configuration Details

The WarpStream agent is configured with:
- **Bucket URL**: `gs://warpstream-tableflow-demo-<random-suffix>`
- **Authentication**: Service account JSON key
- **Environment Variables**:
  - `GOOGLE_APPLICATION_CREDENTIALS`: Path to service account JSON
  - `GCP_PROJECT`: Project ID

**Trino Configuration:**
- Native GCS filesystem enabled (`fs.native-gcs.enabled=true`)
- Direct GCS access without Hadoop
- Project-specific configuration
- Service account credentials from Kubernetes secret

### Verifying Data

```bash
# List files in GCS
gsutil ls -r gs://warpstream-tableflow-demo-<suffix>/warpstream/_tableflow/

# Download a file
gsutil cp gs://warpstream-tableflow-demo-<suffix>/path/to/file ./local-file

# View bucket details
gsutil ls -L -b gs://warpstream-tableflow-demo-<suffix>
```

### Query with Trino

```bash
# Show tables
kubectl exec -n trino deployment/trino -- trino --execute \
  'SHOW TABLES FROM iceberg.default'

# Query orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'
```

### Pros
- ✅ Production-ready and highly scalable
- ✅ **Native Trino GCS support** - optimal performance
- ✅ Strong consistency (no eventual consistency delays)
- ✅ Integrated with Google Cloud IAM
- ✅ Excellent for BigQuery integration
- ✅ Competitive pricing with lifecycle management

### Cons
- ❌ Requires GCP project and credentials
- ❌ Cloud storage costs
- ❌ Service account key management required

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
- ✅ Hierarchical namespace optimized for analytics

### Cons
- ❌ Requires Azure subscription and credentials
- ❌ May incur cloud storage costs
- ❌ **No Trino query engine support** (azblob:// URI incompatibility)
- ❌ Limited OSS tool compatibility
- ❌ Requires internet connectivity

## MinIO Backend (Local S3-Compatible Storage)

### Overview
MinIO is an open-source, S3-compatible object storage server that runs entirely within your Kubernetes cluster. Perfect for development, testing, and demos. **Works with any cloud provider** - just choose MinIO as your backend regardless of where your WarpStream cluster is deployed.

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
# Set environment variables
export WARPSTREAM_DEPLOY_API_KEY='your_api_key'
export TABLEFLOW_BACKEND='minio'

# Works with any cloud provider for WarpStream cluster
# AWS example
export CLOUD_PROVIDER='aws'
export TABLEFLOW_REGION='us-east-1'

# Azure example
export CLOUD_PROVIDER='azure'
export TABLEFLOW_REGION='eastus'

# GCP example
export CLOUD_PROVIDER='gcp'
export TABLEFLOW_REGION='us-central1'

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
- ✅ **Works with any cloud provider** (AWS, Azure, GCP)
- ✅ No cloud storage credentials or subscription required
- ✅ **Trino query engine support** via S3A
- ✅ Fast and easy setup
- ✅ Perfect for development and testing
- ✅ No cloud storage costs - uses cluster resources
- ✅ Works offline / air-gapped environments
- ✅ S3-compatible API (widely supported)
- ✅ Built-in web console for easy data inspection

### Cons
- ❌ Not recommended for production use
- ❌ Limited by cluster storage capacity
- ❌ Data persistence depends on K8s storage class
- ❌ Less scalable than cloud solutions
- ❌ Requires cluster resources (CPU, memory, storage)
- ❌ Trino uses S3A (not native S3) - slightly lower performance

## Switching Between Backends

### Changing Backend After Initial Setup

To switch from one backend to another:

```bash
# 1. Clean up existing deployment
./demo-cleanup.sh

# 2. Set the new cloud provider, region, and backend
export CLOUD_PROVIDER='aws'           # or 'azure', 'gcp'
export TABLEFLOW_REGION='us-east-1'   # provider-specific region
export TABLEFLOW_BACKEND='cloud'      # or 'minio'

# 3. Run the demo again
./demo-startup.sh
```

### Example Configurations

**AWS Production (S3 + Trino):**
```bash
export CLOUD_PROVIDER='aws'
export TABLEFLOW_REGION='us-east-1'
export TABLEFLOW_BACKEND='cloud'
```

**Azure Production (ADLS Gen2, no Trino):**
```bash
export CLOUD_PROVIDER='azure'
export TABLEFLOW_REGION='eastus'
export TABLEFLOW_BACKEND='cloud'
```

**GCP Production (GCS + Trino):**
```bash
export CLOUD_PROVIDER='gcp'
export TABLEFLOW_REGION='us-central1'
export TABLEFLOW_BACKEND='cloud'
```

**Any Cloud Development (MinIO + Trino):**

```bash
export CLOUD_PROVIDER='aws'  # Or 'azure', 'gcp' - only affects WarpStream cluster location
export TABLEFLOW_BACKEND='minio'
```

### Running Multiple Backends Simultaneously

It's technically possible to run cloud and MinIO backends simultaneously (they use separate namespaces), but it's not recommended as:
- The WarpStream agent can only connect to one backend at a time
- You would need multiple WarpStream Tableflow clusters
- Resource usage would be significantly increased

## Architecture Differences

### AWS S3 Architecture

```
┌─────────────────────────┐
│  Kubernetes Cluster     │
│                         │
│  ┌──────────────────┐   │         ┌─────────────────┐
│  │ WarpStream Agent │───┼────────►│   AWS Cloud     │
│  │                  │   │         │                 │
│  │ - AWS creds      │   │         │   S3 Bucket     │
│  └──────────────────┘   │         │   (s3://)       │
│                         │         └────────┬────────┘
│  ┌──────────────────┐   │                  │
│  │  Trino Engine    │───┼──────────────────┘
│  │  (Native S3)     │   │      Direct S3 access
│  └──────────────────┘   │
└─────────────────────────┘

Data Flow: Kafka → WarpStream Agent → S3 → Trino (Native S3)
```

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
│                         │         │  (azblob://)    │
└─────────────────────────┘         └─────────────────┘

Note: No Trino support - azblob:// URIs incompatible with OSS query engines
Data Flow: Kafka → WarpStream Agent → ADLS Gen2 (no query engine)
```

### GCP Cloud Storage Architecture

```
┌─────────────────────────┐
│  Kubernetes Cluster     │
│                         │
│  ┌──────────────────┐   │         ┌─────────────────┐
│  │ WarpStream Agent │───┼────────►│   GCP Cloud     │
│  │                  │   │         │                 │
│  │ - GCP SA creds   │   │         │   GCS Bucket    │
│  └──────────────────┘   │         │   (gs://)       │
│                         │         └────────┬────────┘
│  ┌──────────────────┐   │                  │
│  │  Trino Engine    │───┼──────────────────┘
│  │  (Native GCS)    │   │      Direct GCS access
│  └──────────────────┘   │
└─────────────────────────┘

Data Flow: Kafka → WarpStream Agent → GCS → Trino (Native GCS)
```

### MinIO Architecture (Local Storage)

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
│                         └─────┬─────┘  │
│  ┌──────────────────┐         │        │
│  │  Trino Engine    │─────────┘        │
│  │  (S3A protocol)  │   S3-compatible  │
│  └──────────────────┘                  │
└─────────────────────────────────────────┘

Data Flow: Kafka → WarpStream Agent → MinIO → Trino (S3A)
Note: All components run in same Kubernetes cluster
```

## Environment Variables Reference

### Common Variables (All Backends)

```bash
WARPSTREAM_DEPLOY_API_KEY       # Required: WarpStream account API key
CLOUD_PROVIDER                  # Optional: 'aws', 'azure', or 'gcp' (interactive if not set)
TABLEFLOW_REGION                # Optional: Cloud-specific region (interactive if not set)
TABLEFLOW_BACKEND               # Optional: 'cloud' or 'minio' (interactive if not set)
WARPSTREAM_NAMESPACE            # Optional: WarpStream K8s namespace (default: warpstream)
CONFLUENT_NAMESPACE             # Optional: Confluent K8s namespace (default: confluent)
```

### AWS-Specific Variables

```bash
# For Confluent Employees (prompted during deployment)
CONFLUENT_EMPLOYEE              # Optional: 'true' or 'false' (interactive if not set)
AWS_PROFILE                     # Optional: AWS CLI profile to use
AWS_DEFAULT_REGION              # Set automatically from TABLEFLOW_REGION

# Authentication handled automatically via:
# - AWS SSO + assume role (Confluent employees)
# - AWS CLI credentials (non-Confluent)
```

### Azure-Specific Variables

```bash
AZURE_SUBSCRIPTION_ID           # Optional: Azure subscription (interactive if not set)
AZURE_TENANT_ID                 # Optional: Azure tenant ID
AZURE_LOGIN_SCOPE               # Optional: Azure login scope
```

### GCP-Specific Variables

```bash
GCP_PROJECT                     # Optional: GCP project ID (interactive if not set)
GCP_REGION                      # Set automatically from TABLEFLOW_REGION

# Service account created automatically during deployment
# Credentials stored in Kubernetes secrets
```

### MinIO-Specific Variables

```bash
MINIO_NAMESPACE                 # Optional: MinIO K8s namespace (default: minio)
MINIO_CONSOLE_PORT              # Optional: MinIO console port (default: 9001)
# Note: MinIO credentials are hardcoded as minioadmin/minioadmin
```

### Trino-Specific Variables

```bash
TRINO_UI_PORT                   # Optional: Trino UI port (default: 8080)
# Trino automatically deployed for: AWS (cloud), GCP (cloud), MinIO
# Trino NOT deployed for: Azure (cloud) - URI incompatibility
```

## Troubleshooting

### Azure Backend Issues

#### Authentication Failures

The demo requires you to authenticate with Azure CLI **before** running the script.

```bash
# Authenticate with Azure
az login

# List available subscriptions
az account list --output table

# Set the subscription you want to use
az account set --subscription YOUR_SUBSCRIPTION_ID

# Verify authentication
az account show

# Now run the demo
./demo-startup.sh
```

**Note:** The script will use your currently active subscription. It no longer prompts for subscription selection interactively. If you need to change subscriptions, use `az account set` before running the demo.

#### Token Expiration During Deployment

If you see errors like:
```
Error: building account: could not acquire access token
ERROR: AADSTS70043: The refresh token has expired or is invalid
```

This means your Azure token expired. The script validates tokens before Terraform runs, but if you see this:

```bash
# Re-authenticate
az logout
az login --tenant YOUR_TENANT_ID

# Set subscription
az account set --subscription YOUR_SUBSCRIPTION_ID

# Retry the demo
./demo-startup.sh
```

**Token Lifespan:** Azure tokens typically last 1-2 hours, but conditional access policies can shorten this. If you're taking breaks between demo steps, you may need to re-authenticate.

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
- ✅ Trino query engine included
- ✅ Easy data inspection via web console
- ✅ Can run completely offline
- ✅ Works with any WarpStream cluster location (AWS, Azure, GCP)

### For Production

**Choose based on your cloud provider:**

- **AWS Production:**
  - ✅ Use **AWS S3 backend** with native Trino support
  - ✅ Best performance with native S3 filesystem
  - ✅ IAM-based access control
  - ✅ Global availability and scalability

- **Azure Production:**
  - ✅ Use **Azure ADLS Gen2 backend**
  - ✅ Native Azure integration and compliance
  - ⚠️ No Trino support - consider if SQL analytics needed
  - ✅ Hierarchical namespace optimization

- **GCP Production:**
  - ✅ Use **GCP Cloud Storage backend** with native Trino support
  - ✅ Strong consistency guarantees
  - ✅ Excellent BigQuery integration
  - ✅ Competitive pricing

### For Demos/Workshops

- ✅ **MinIO** for quick setup with no prerequisites
  - Works with any cloud provider choice
  - Trino included for SQL demonstrations
  - No cloud costs or credential setup
  
- ✅ **Cloud backends** to showcase production architecture
  - **AWS S3** - Show native S3 with Trino
  - **Azure ADLS Gen2** - Enterprise Azure integration (no Trino)
  - **GCP GCS** - Show native GCS with Trino
  
- 💡 **Consider your audience:**
  - Developers → MinIO for hands-on
  - Architects → Cloud backend for production patterns
  - Multi-cloud audience → Show provider selection flow

### Query Engine Requirements

- ✅ **Need SQL analytics?** Choose AWS S3, GCP GCS, or MinIO
- ❌ **Azure ADLS Gen2** does not support Trino (azblob:// incompatibility)
- 📖 See [OSS_QUERY_ENGINES.md](OSS_QUERY_ENGINES.md) for technical details

## Additional Resources

- [MinIO Documentation](https://min.io/docs/)
- [MinIO Kubernetes Guide](https://min.io/docs/minio/kubernetes/upstream/)
- [Azure ADLS Gen2 Documentation](https://learn.microsoft.com/en-us/azure/storage/blobs/data-lake-storage-introduction)
- [WarpStream Tableflow Documentation](https://docs.warpstream.com/)
- [MinIO Console Guide](https://min.io/docs/minio/linux/administration/minio-console.html)
