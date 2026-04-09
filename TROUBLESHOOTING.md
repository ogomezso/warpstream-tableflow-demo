# Troubleshooting Guide

This guide helps resolve common issues you may encounter while running the demo.

## Table of Contents

- [Azure Authentication Issues](#azure-authentication-issues)
- [Port-Forward Issues](#port-forward-issues)
- [Trino Query Failures](#trino-query-failures)
- [No Data in Tables](#no-data-in-tables)
- [WarpStream Agent Issues](#warpstream-agent-issues)
- [Kubernetes Issues](#kubernetes-issues)
- [Cleanup Issues](#cleanup-issues)

## Azure Authentication Issues

### Problem: Azure token expired or conditional access errors

**Symptoms:**
- "Interactive authentication is needed" error
- "Conditional access policy requires device compliance"
- Token refresh errors

**Solution:**

The script automatically handles Azure authentication, including expired refresh tokens. If you encounter authentication issues:

```bash
# Standard re-authentication
az logout
az login

# If you have conditional access policies requiring specific scopes
export AZURE_LOGIN_SCOPE='https://graph.microsoft.com/.default'
az logout
az login --scope $AZURE_LOGIN_SCOPE

# List available subscriptions
az account list --output table

# Set specific subscription
az account set --subscription "your-subscription-id"
```

**Automatic Token Refresh:**
The script detects and automatically re-authenticates when your Azure token expires due to conditional access policies (e.g., 12-hour session limits).

### Problem: Wrong Azure subscription selected

**Solution:**
```bash
# Check current subscription
az account show

# Set correct subscription
export AZURE_SUBSCRIPTION_ID='your-subscription-id'
./demo-startup.sh
```

## Port-Forward Issues

### Problem: Port-forwards not working or ports already in use

**Symptoms:**
- "unable to listen on port"
- UIs not accessible at localhost URLs
- "bind: address already in use"

**Solution:**

```bash
# Check if port-forwards are running
ps aux | grep "port-forward"

# Stop all port-forwards
pkill -f "port-forward"

# Or stop specific ones
pkill -f "port-forward.*controlcenter"
pkill -f "port-forward.*minio"
pkill -f "port-forward.*trino"

# Restart demo (will skip deployment, just setup port-forwards)
./demo-startup.sh
```

### Problem: Port-forward died unexpectedly

**Solution:**
```bash
# Manually restart Control Center port-forward
kubectl port-forward -n confluent svc/controlcenter-ng 9021:9021 &

# Manually restart MinIO Console port-forward
kubectl port-forward -n minio svc/minio 9001:9001 &

# Manually restart Trino UI port-forward
kubectl port-forward -n trino svc/trino 8080:8080 &
```

## Trino Query Failures

### Problem: "Error processing metadata for table"

**Symptoms:**
- SELECT queries fail
- `SHOW TABLES` works but queries fail
- Generic "GENERIC_INTERNAL_ERROR"

**Diagnostic Steps:**

```bash
# 1. Check Trino pod status
kubectl get pods -n trino

# 2. Check Trino logs
kubectl logs -n trino deployment/trino --tail=100

# 3. Verify MinIO connectivity from Trino
kubectl exec -n trino deployment/trino -- curl -s http://minio.minio.svc.cluster.local:9000

# 4. Test simple query
kubectl exec -n trino deployment/trino -- trino --execute "SHOW CATALOGS"
```

**Common Causes:**

1. **Wrong backend** - Trino only works with MinIO, not Azure
   ```bash
   # Check which backend is deployed
   kubectl get namespace minio
   ```

2. **MinIO not accessible**
   ```bash
   # Verify MinIO is running
   kubectl get pods -n minio
   kubectl logs -n minio deployment/minio --tail=50
   ```

3. **Credentials mismatch**
   ```bash
   # Check Trino deployment env vars
   kubectl get deployment trino -n trino -o yaml | grep -A 5 "env:"
   ```

### Problem: "Query is gone (server restarted?)"

**Solution:**
```bash
# Trino pod restarted, wait for it to be ready
kubectl wait --for=condition=ready pod -l app=trino -n trino --timeout=120s

# Then retry query
```

## No Data in Tables

### Problem: Table exists but has no data

**Diagnostic Steps:**

```bash
# 1. Check WarpStream agent is running
kubectl get pods -n warpstream

# 2. Check WarpStream agent logs
kubectl logs -n warpstream deployment/warpstream-agent --tail=50

# 3. Check Kafka Connect datagen connector
kubectl get pods -n confluent | grep connect

# 4. Check if data is flowing to Kafka
kubectl exec -n confluent kafka-0 -- kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic datagen-orders \
  --max-messages 5

# 5. Check Tableflow pipeline status
kubectl get pipelines -n warpstream
kubectl describe pipeline -n warpstream
```

**Common Causes:**

1. **Datagen connector not running**
   ```bash
   kubectl logs -n confluent deployment/connect --tail=50
   ```

2. **WarpStream agent errors**
   ```bash
   kubectl logs -n warpstream deployment/warpstream-agent | grep -i error
   ```

3. **Pipeline not created**
   ```bash
   kubectl get pipeline -n warpstream orders-tableflow-pipeline
   ```

## WarpStream Agent Issues

### Problem: "failed to determine availability zone"

**Symptoms:**
- Agent logs show availability zone errors
- Agent crashes or restarts

**Solution:**
This is expected in local Kubernetes clusters. The agent configuration includes:
```yaml
env:
  - name: WARPSTREAM_AVAILABILITY_ZONE
    value: "local-k8s-cluster"
```

If still failing:
```bash
# Check agent configuration
kubectl get deployment warpstream-agent -n warpstream -o yaml | grep -A 5 AVAILABILITY_ZONE

# Restart agent
kubectl rollout restart deployment/warpstream-agent -n warpstream
```

### Problem: Agent can't write to storage

**For MinIO:**
```bash
# Verify MinIO is accessible
kubectl exec -n warpstream deployment/warpstream-agent -- \
  curl -s http://minio.minio.svc.cluster.local:9000

# Check credentials secret
kubectl get secret minio-storage-credentials -n warpstream -o yaml
```

**For Azure:**
```bash
# Check Azure credentials secret
kubectl get secret azure-storage-secret -n confluent -o yaml

# Verify storage account exists
az storage account show --name wsdemostore
```

## Kubernetes Issues

### Problem: Namespace stuck in "Terminating" state

**Solution:**
```bash
# This is normal during cleanup - K8s is removing finalizers
# Wait up to 2-3 minutes, then check again
kubectl get namespace <namespace>

# If stuck for >5 minutes, force cleanup
kubectl get namespace <namespace> -o json | \
  jq '.spec.finalizers = []' | \
  kubectl replace --raw /api/v1/namespaces/<namespace>/finalize -f -
```

### Problem: Pod stuck in "Pending" state

**Diagnostic:**
```bash
# Check pod details
kubectl describe pod <pod-name> -n <namespace>

# Common issues:
# - Insufficient resources
# - PVC not bound
# - Image pull errors
```

### Problem: PVC not binding (MinIO)

**Solution:**
```bash
# Check storage class
kubectl get storageclass

# Check PVC status
kubectl get pvc -n minio

# If no default storage class, create one or specify explicitly
```

## Cleanup Issues

### Problem: `CLEANUP_REMOVE_CFK_OPERATOR=false` not working

**Solution:**
Make sure to export the variable before running cleanup:
```bash
export CLEANUP_REMOVE_CFK_OPERATOR=false
./demo-cleanup.sh
```

### Problem: Azure resources not deleted

**Check:**
```bash
# Verify Azure login
az account show

# Check if Terraform state exists
ls -la environment/azure/.terraform
ls -la environment/azure/terraform.tfstate

# Manually destroy if needed
cd environment/azure
terraform destroy
```

### Problem: MinIO namespace won't delete

**Cause:** PVC has finalizers

**Solution:**
```bash
# Delete PVC first
kubectl delete pvc --all -n minio

# Then delete namespace
kubectl delete namespace minio
```

## Verification Commands

### Check Overall Demo Status

```bash
# All namespaces
kubectl get namespaces | grep -E "confluent|warpstream|minio|trino"

# All pods
kubectl get pods -A | grep -E "confluent|warpstream|minio|trino"

# All services
kubectl get svc -A | grep -E "confluent|warpstream|minio|trino"

# Port-forwards
ps aux | grep port-forward
```

### Check Data Flow

```bash
# 1. Datagen producing
kubectl logs -n confluent deployment/connect --tail=20 | grep datagen

# 2. Kafka has data
kubectl exec -n confluent kafka-0 -- kafka-console-consumer \
  --bootstrap-server kafka:9092 \
  --topic datagen-orders \
  --max-messages 3

# 3. WarpStream processing
kubectl logs -n warpstream deployment/warpstream-agent --tail=20

# 4. MinIO has files
kubectl exec -n minio deployment/minio -- \
  ls -la /data/tableflow/warpstream/_tableflow/

# 5. Trino can query
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'
```

## Getting Help

If you're still experiencing issues:

1. **Check logs** for all components:
   ```bash
   kubectl logs -n confluent deployment/connect --tail=100
   kubectl logs -n warpstream deployment/warpstream-agent --tail=100
   kubectl logs -n minio deployment/minio --tail=100
   kubectl logs -n trino deployment/trino --tail=100
   ```

2. **Collect diagnostics**:
   ```bash
   kubectl get all -n confluent
   kubectl get all -n warpstream
   kubectl get all -n minio
   kubectl get all -n trino
   ```

3. **Review documentation**:
   - [README.md](README.md) - Main documentation
   - [ARCHITECTURE.md](ARCHITECTURE.md) - Architecture details
   - [BACKEND_OPTIONS.md](BACKEND_OPTIONS.md) - Backend comparison

4. **Report issues**:
   - Check [OSS_QUERY_ENGINES.md](OSS_QUERY_ENGINES.md) for known Trino/Azure limitations
   - File issues at the appropriate GitHub repository
