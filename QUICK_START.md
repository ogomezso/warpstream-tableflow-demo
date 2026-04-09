# Quick Start Guide - MinIO Backend with Trino

Complete zero-to-running guide including Kubernetes cluster setup and WarpStream account creation.

## Setup Prerequisites

### 1. Kubernetes Cluster Setup (Kind)

If you don't have a Kubernetes cluster, [Kind](https://kind.sigs.k8s.io/) (Kubernetes in Docker) is the easiest option.

**Install Kind:**

```bash
# macOS
brew install kind

# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

# Windows (PowerShell)
curl.exe -Lo kind-windows-amd64.exe https://kind.sigs.k8s.io/dl/v0.20.0/kind-windows-amd64
Move-Item .\kind-windows-amd64.exe c:\some-dir-in-your-PATH\kind.exe
```

**Create a Kind cluster:**

```bash
# Create cluster with recommended configuration
kind create cluster --name warpstream-demo --config - <<EOF
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
  extraPortMappings:
  - containerPort: 9021
    hostPort: 9021
    protocol: TCP
  - containerPort: 9001
    hostPort: 9001
    protocol: TCP
  - containerPort: 8080
    hostPort: 8080
    protocol: TCP
EOF

# Verify cluster is running
kubectl cluster-info --context kind-warpstream-demo
kubectl get nodes
```

**Resource Recommendations:**
- **Minimum:** 4 CPU cores, 8GB RAM
- **Recommended:** 6 CPU cores, 12GB RAM

Configure Docker Desktop resources: Docker → Preferences → Resources

**Delete cluster when done:**
```bash
kind delete cluster --name warpstream-demo
```

### 2. WarpStream Account Setup

**Create WarpStream Account:**

1. Visit [console.warpstream.com](https://console.warpstream.com)
2. Click **Sign Up** (free tier available)
3. Complete registration with email verification
4. Choose a region for your virtual cluster (e.g., `us-east-1`, `eastus`)

**Generate Deploy API Key:**

The Deploy API Key is used by Terraform to provision WarpStream resources.

1. Log in to [WarpStream Console](https://console.warpstream.com)
2. Navigate to **Settings** → **API Keys**
3. Click **Create API Key**
4. Select **Account API Key** type
   - ⚠️ **NOT** "Agent Key" (agent keys start with `aki_`)
   - ⚠️ Deploy API key is for Terraform authentication
5. (Optional) Add a description: "Tableflow Demo Terraform"
6. Click **Create**
7. **Copy the key immediately** (shown only once)

**Set Environment Variable:**

```bash
export WARPSTREAM_DEPLOY_API_KEY='your_key_here'

# Verify it's set
echo $WARPSTREAM_DEPLOY_API_KEY
```

**Key Types Comparison:**

| Key Type | Starts With | Used By | Purpose |
|----------|-------------|---------|---------|
| **Deploy API Key** | (no prefix) | Terraform | Create clusters, agent keys, pipelines |
| **Agent Key** | `aki_` | WarpStream Agent | Connect agents to clusters |

### 3. Install Required Tools

**Helm (Kubernetes package manager):**

```bash
# macOS
brew install helm

# Linux
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Windows (PowerShell)
choco install kubernetes-helm

# Verify
helm version
```

**Terraform (Infrastructure as Code):**

```bash
# macOS
brew tap hashicorp/tap
brew install hashicorp/tap/terraform

# Linux
wget -O- https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update && sudo apt install terraform

# Windows (PowerShell)
choco install terraform

# Verify
terraform version
```

**kubectl (Kubernetes CLI):**

Usually installed with Kind or Docker Desktop. If not:

```bash
# macOS
brew install kubectl

# Linux
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Windows (PowerShell)
choco install kubernetes-cli

# Verify
kubectl version --client
```

## Pre-Flight Check

Verify everything is ready:

```bash
# Check Kubernetes cluster
kubectl cluster-info
kubectl get nodes

# Check tools
kubectl version --client
helm version
terraform version

# Check WarpStream API key
echo $WARPSTREAM_DEPLOY_API_KEY
```

Expected output: All commands succeed with version information.

## Deploy

```bash
# Option 1: Pre-select MinIO backend
export TABLEFLOW_BACKEND='minio'
./demo-startup.sh

# Option 2: Interactive selection (choose option 2)
./demo-startup.sh
```

Deployment takes ~5-7 minutes. All port-forwards are set up automatically!

## Access UIs

Once deployment completes, these URLs are immediately available:

| UI | URL | Credentials | Purpose |
|----|-----|-------------|---------|
| **Confluent Control Center** | <http://localhost:9021> | - | Monitor Kafka topics and connectors |
| **MinIO Console** | <http://localhost:9001> | minioadmin / minioadmin | Browse Iceberg tables and Parquet files |
| **Trino Query UI** | <http://localhost:8080> | - | View query history and metrics |

> **Note**: All UIs are automatically port-forwarded - just click the links!

## Query Data with Trino

### Quick Queries (Copy & Paste)

```bash
# Show available tables
kubectl exec -n trino deployment/trino -- trino --execute \
  'SHOW TABLES FROM iceberg.default'

# Count total orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'

# View sample orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT orderid, itemid, orderunits, address.city, address.state 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   LIMIT 10'

# Top 5 states by order count
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT address.state, COUNT(*) as orders 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   GROUP BY address.state 
   ORDER BY orders DESC 
   LIMIT 5'

# Average order units by state
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT address.state, 
          ROUND(AVG(orderunits), 2) as avg_units,
          COUNT(*) as order_count
   FROM iceberg.default."cp_cluster__datagen-orders" 
   GROUP BY address.state 
   ORDER BY avg_units DESC 
   LIMIT 10'
```

### Interactive Trino CLI

```bash
# Start interactive SQL shell
kubectl exec -it -n trino deployment/trino -- trino

# Then run queries interactively:
trino> SHOW SCHEMAS FROM iceberg;
trino> USE iceberg.default;
trino> DESCRIBE "cp_cluster__datagen-orders";
trino> SELECT * FROM "cp_cluster__datagen-orders" LIMIT 5;
trino> quit;
```

## Verify Data Flow

### 1. Check Confluent Control Center

Open <http://localhost:9021>:
- Navigate to **Topics** → `datagen-orders`
- See messages flowing in real-time
- Check **Connect** → Connectors → `datagen-orders`

### 2. Check MinIO Console

Open <http://localhost:9001> (login: minioadmin/minioadmin):
- Navigate to **Buckets** → `tableflow` → `warpstream/_tableflow/`
- See Iceberg table directory: `cp_cluster__datagen-orders-<uuid>`
- Browse `data/` folder for Parquet files
- Browse `metadata/` folder for Iceberg metadata

### 3. Check Trino UI

Open <http://localhost:8080>:
- View recent queries in the dashboard
- Click on a query to see execution details
- Check query performance and data scanned

## Example Workflow

```bash
# 1. Check how many orders are in the system
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'
# Output: 12769 (or similar)

# 2. Wait 30 seconds for more data to flow in
sleep 30

# 3. Check again - should see more orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT COUNT(*) FROM iceberg.default."cp_cluster__datagen-orders"'
# Output: Higher number

# 4. Analyze the latest orders
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT orderid, itemid, address.state, orderunits 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   ORDER BY ordertime DESC 
   LIMIT 10'
```

## Advanced Queries

```bash
# Find high-value orders (> 8 units)
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT orderid, itemid, orderunits, address.state 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   WHERE orderunits > 8.0 
   ORDER BY orderunits DESC 
   LIMIT 20'

# Orders by city and state
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT address.city, address.state, COUNT(*) as orders 
   FROM iceberg.default."cp_cluster__datagen-orders" 
   GROUP BY address.city, address.state 
   ORDER BY orders DESC 
   LIMIT 20'

# Distribution of order sizes
kubectl exec -n trino deployment/trino -- trino --execute \
  'SELECT 
     CASE 
       WHEN orderunits < 2 THEN "Small (0-2)"
       WHEN orderunits < 5 THEN "Medium (2-5)"
       WHEN orderunits < 8 THEN "Large (5-8)"
       ELSE "XLarge (8+)"
     END as order_size,
     COUNT(*) as count
   FROM iceberg.default."cp_cluster__datagen-orders"
   GROUP BY 1
   ORDER BY count DESC'
```

## Cleanup

```bash
export WARPSTREAM_DEPLOY_API_KEY='your_warpstream_account_api_key'
./demo-cleanup.sh
```

Cleanup automatically stops all port-forwards and removes all resources.

## Troubleshooting

### Port-forwards not working?

```bash
# Check if port-forwards are running
ps aux | grep "port-forward"

# Manually restart if needed
pkill -f "port-forward"
./demo-startup.sh  # Will skip deployment, just setup port-forwards
```

### Trino query failing?

```bash
# Check Trino pod status
kubectl get pods -n trino

# Check Trino logs
kubectl logs -n trino deployment/trino --tail=50

# Verify MinIO connectivity
kubectl exec -n trino deployment/trino -- curl -s http://minio.minio.svc.cluster.local:9000
```

### No data in tables?

```bash
# Check WarpStream agent
kubectl get pods -n warpstream
kubectl logs -n warpstream deployment/warpstream-agent --tail=50

# Check Tableflow pipeline
kubectl get pipelines -n warpstream
```

## Time Travel Queries

Iceberg's snapshot isolation enables querying historical data:

```bash
# Unified query interface (recommended)
./demo-query.sh time-travel

# Or use interactive menu
./demo-query.sh
```

**Features:**
- 📊 **Beautiful table formatting** - Easy-to-read aligned columns
- 📈 **Total row count shown** - Know how many rows before selecting limit
- 📸 **Snapshot comparison** - See changes between snapshots with percentages
- 🎯 **Smart defaults** - Automatic capping at max available rows

The script will:
1. Show all available snapshots with timestamps
2. Display total row count in selected snapshot
3. Let you choose how many rows to view
4. Show data in formatted table
5. Compare snapshot vs current with statistics

**Manual time travel:**
```bash
# Query by snapshot ID
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT * FROM iceberg.default.\"cp_cluster__datagen-orders\" 
   FOR VERSION AS OF 1775740640545456000 
   LIMIT 10"

# View all snapshots
kubectl exec -n trino deployment/trino -- trino --execute \
  "SELECT snapshot_id, committed_at 
   FROM iceberg.default.\"cp_cluster__datagen-orders\$snapshots\"
   ORDER BY committed_at DESC"
```

See [README.md](README.md#time-travel-queries) for more examples.

## What's Next?

- Explore the [full README](README.md) for detailed documentation
- Check [BACKEND_OPTIONS.md](BACKEND_OPTIONS.md) for backend comparison
- See [environment/trino/README-MINIO.md](environment/trino/README-MINIO.md) for Trino architecture
- Review [OSS_QUERY_ENGINES.md](OSS_QUERY_ENGINES.md) for why Trino works with MinIO but not Azure

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Kubernetes Cluster                       │
│                                                             │
│  ┌──────────────┐  ┌──────────┐  ┌───────────┐            │
│  │  Confluent   │  │ WarpStream│  │   MinIO   │            │
│  │   Platform   │→ │   Agent   │→ │  Storage  │            │
│  │   (Kafka)    │  │ +Pipeline │  │(Tableflow)│            │
│  └──────────────┘  └──────────┘  └─────↑─────┘            │
│         ↓                                │                  │
│  ┌──────────────────────────────────────┴──────┐           │
│  │           Trino Query Engine                │           │
│  │     (Queries Iceberg via S3A)               │           │
│  └─────────────────────────────────────────────┘           │
└─────────────────────────────────────────────────────────────┘

Data Flow:
1. Kafka Connect generates orders → datagen-orders topic
2. WarpStream Tableflow pipeline transforms → Iceberg tables
3. Iceberg tables stored in MinIO (S3-compatible)
4. Trino queries Iceberg tables via Hadoop S3A
```

---

**🎉 You're all set!** Start querying your Iceberg tables with Trino!
