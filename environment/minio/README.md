# MinIO Backend for WarpStream Tableflow

This directory contains Kubernetes manifests to deploy MinIO as an S3-compatible object storage backend for WarpStream Tableflow.

## Overview

MinIO provides a lightweight, S3-compatible object storage solution that runs entirely within your Kubernetes cluster. This is ideal for:

- **Development and testing** - No cloud credentials required
- **Local demos** - Everything runs in your cluster
- **Air-gapped environments** - No external dependencies
- **Cost optimization** - No cloud storage costs for demos

## Components

### Namespace (`namespace.yaml`)
Creates the `minio` namespace for all MinIO resources.

### Deployment (`deployment.yaml`)
Deploys:
- **MinIO server** - S3-compatible object storage
- **PersistentVolumeClaim** - 10Gi storage for data persistence
- **Service** - ClusterIP service exposing:
  - Port 9000: MinIO API (S3-compatible)
  - Port 9001: MinIO Console (web UI)

### Initialization Job (`init-job.yaml`)
A Kubernetes Job that:
- Waits for MinIO to be ready
- Creates the `tableflow` bucket
- Configures MinIO for WarpStream usage

### Deployment Script (`deploy.sh`)
Automated deployment script that:
1. Creates the MinIO namespace
2. Deploys MinIO server
3. Waits for MinIO to be ready
4. Runs initialization job to create bucket

## Configuration

### Default Credentials
- **Access Key**: `minioadmin`
- **Secret Key**: `minioadmin`

⚠️ **Warning**: These are default credentials suitable for development only. For production use, change these credentials.

### Storage
- **Default Size**: 10Gi PersistentVolumeClaim
- **StorageClass**: Uses cluster default StorageClass
- **Access Mode**: ReadWriteOnce

### Bucket
- **Name**: `tableflow`
- **Region**: `us-east-1`

## Usage

### Deploy MinIO
```bash
# Deploy MinIO to Kubernetes
./deploy.sh

# Or manually
kubectl apply -f namespace.yaml
kubectl apply -f deployment.yaml
kubectl apply -f init-job.yaml
```

### Access MinIO Console
```bash
# Port-forward to access web console
kubectl port-forward -n minio svc/minio 9001:9001

# Open browser to http://localhost:9001
# Login with: minioadmin / minioadmin
```

### Access MinIO API
```bash
# Port-forward to access S3 API
kubectl port-forward -n minio svc/minio 9000:9000

# MinIO API is now available at http://localhost:9000
```

### Using MinIO CLI (mc)
```bash
# Install MinIO client
brew install minio/stable/mc  # macOS
# or download from https://min.io/docs/minio/linux/reference/minio-mc.html

# Configure alias
kubectl port-forward -n minio svc/minio 9000:9000 &
mc alias set local http://localhost:9000 minioadmin minioadmin

# List buckets
mc ls local

# Browse tableflow bucket
mc ls local/tableflow
```

### Inspect Data
```bash
# View objects in tableflow bucket
mc ls local/tableflow/warpstream/

# Download an object
mc cp local/tableflow/warpstream/path/to/object ./local-file
```

## Integration with WarpStream

When using MinIO backend, the WarpStream agent is configured with:

```yaml
config:
  # Note: For MinIO, s3ForcePathStyle and endpoint must be in the bucket URL
  # The URL must be quoted due to special characters (http://)
  bucketURL: "s3://tableflow?region=us-east-1&s3ForcePathStyle=true&endpoint=http://minio.minio.svc.cluster.local:9000"

extraEnv:
  - name: WARPSTREAM_AVAILABILITY_ZONE
    value: "local-k8s-cluster"  # Required for local deployments
  - name: AWS_ACCESS_KEY_ID
    value: minioadmin
  - name: AWS_SECRET_ACCESS_KEY
    valueFrom:
      secretKeyRef:
        name: minio-storage-credentials
        key: secret-key
```

**Note**: The `WARPSTREAM_AVAILABILITY_ZONE` environment variable is required for local Kubernetes deployments. WarpStream agents normally auto-detect the availability zone from cloud provider metadata (AWS/GCP/Azure), but this fails in local environments. Setting it explicitly prevents errors during agent startup.

## Cleanup

```bash
# Delete all MinIO resources
kubectl delete -f deployment.yaml
kubectl delete -f init-job.yaml
kubectl delete -f namespace.yaml

# Or use the cleanup script
../../demo-cleanup.sh
```

## Troubleshooting

### MinIO pod not starting
```bash
# Check pod status
kubectl get pods -n minio

# View pod logs
kubectl logs -n minio deployment/minio

# Check PVC status
kubectl get pvc -n minio
```

### Bucket not created
```bash
# Check init job status
kubectl get jobs -n minio

# View init job logs
kubectl logs -n minio job/minio-init

# Manually create bucket
kubectl port-forward -n minio svc/minio 9000:9000 &
mc alias set local http://localhost:9000 minioadmin minioadmin
mc mb local/tableflow
```

### Cannot access console
```bash
# Verify service is running
kubectl get svc -n minio

# Check MinIO pod health
kubectl get pods -n minio
kubectl describe pod -n minio -l app=minio

# Verify port-forward
kubectl port-forward -n minio svc/minio 9001:9001
```

### WarpStream agent DNS errors (bucket.minio.svc.cluster.local not found)
If you see errors like `lookup tableflow.minio.minio.svc.cluster.local: no such host`:

**Cause**: WarpStream is using virtual-hosted-style S3 URLs instead of path-style URLs.

**Solution**: For WarpStream, the `s3ForcePathStyle=true` parameter must be included **in the bucket URL itself**, not as an environment variable. The correct bucket URL format is:

```yaml
bucketURL: "s3://tableflow?region=us-east-1&s3ForcePathStyle=true&endpoint=http://minio.minio.svc.cluster.local:9000"
```

**Important**: The URL must be quoted in YAML because it contains special characters (`http://`).

This is already configured in the template. If you're troubleshooting:

```bash
# Verify the bucket URL in the agent config
kubectl get deployment -n warpstream warpstream-agent -o yaml | grep bucketURL

# Expected output should show s3ForcePathStyle=true in the URL
# If incorrect, redeploy with the correct template
./demo-cleanup.sh
export TABLEFLOW_BACKEND='minio'
./demo-startup.sh
```

## Production Considerations

For production deployments, consider:

1. **Security**:
   - Change default credentials
   - Use Kubernetes secrets for credentials
   - Enable TLS/SSL
   - Implement RBAC policies

2. **High Availability**:
   - Deploy MinIO in distributed mode
   - Use StatefulSet instead of Deployment
   - Configure multiple replicas

3. **Storage**:
   - Use appropriate StorageClass for your environment
   - Configure adequate storage size
   - Implement backup strategies

4. **Networking**:
   - Use LoadBalancer or Ingress for external access
   - Configure network policies
   - Implement proper DNS resolution

5. **Monitoring**:
   - Enable Prometheus metrics
   - Set up alerting
   - Monitor storage capacity

## References

- [MinIO Documentation](https://min.io/docs/minio/kubernetes/upstream/)
- [MinIO Kubernetes Operator](https://github.com/minio/operator)
- [WarpStream Documentation](https://docs.warpstream.com/)
