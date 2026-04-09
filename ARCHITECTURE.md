# Architecture & Infrastructure

This document provides detailed information about the demo's architecture, infrastructure, and project structure.

## Infrastructure Created

### Azure Resources (Terraform)

When using Azure backend:

| Resource | Name | Description |
|----------|------|-------------|
| Storage Account | `wsdemostore` | ADLS Gen2-enabled Storage Account with LRS replication |
| ADLS Gen2 Filesystem | `tableflow` | Private filesystem for WarpStream data |

Location: `environment/azure/main.tf`

### MinIO Resources (Kubernetes)

When using MinIO backend:

| Resource | Namespace | Description |
|----------|-----------|-------------|
| Deployment | `minio` | MinIO server with 10Gi PVC |
| Service | `minio` | ClusterIP service (API: 9000, Console: 9001) |
| PersistentVolumeClaim | `minio` | 10Gi storage for data |
| Bucket | `tableflow` | Automatically created bucket |

Location: `environment/minio/`

### WarpStream Resources (Terraform)

| Resource | Name | Description |
|----------|------|-------------|
| Tableflow Cluster | `vcn_dl_tableflow_cluster_dev` | Dev-tier Tableflow cluster in specified region |
| Agent Key | `akn_tableflow_demo_agent_key` | Agent key for WarpStream agent authentication |
| Tableflow Pipeline | `orders-pipeline` | Pipeline transforming orders topic to Iceberg |

Location: `environment/warpstream/cluster/main.tf` and `environment/warpstream/tableflow-pipeline/main.tf`

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

| Component | Namespace | Description |
|-----------|-----------|-------------|
| WarpStream Agent | `warpstream` | Agent deployment connecting to Tableflow cluster |
| Service Account | `warpstream` | `warpstream-agent` |
| Secrets | `warpstream` | Backend-specific storage credentials |

Location: `environment/warpstream/agent/`

#### Trino (MinIO Backend Only)

| Component | Namespace | Description |
|-----------|-----------|-------------|
| Trino | `trino` | Query engine with Iceberg connector |
| WarpStream Proxy | `trino` | Nginx proxy injecting auth headers |
| ConfigMap | `trino` | S3A configuration for MinIO |

Location: `environment/trino/`

## Architecture Diagrams

### Azure ADLS Gen2 Backend

```text
┌─────────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                                  │
│                                                                             │
│  ┌─────────────────────────────┐  ┌──────────────────────────┐              │
│  │   Confluent Platform (CFK)  │  │   WarpStream Namespace   │              │
│  │                             │  │                          │              │
│  │  - KRaft Controller         │  │  - WarpStream Agent      │              │
│  │  - Kafka Broker             │  │  - Azure Credentials     │              │
│  │  - Schema Registry          │  │                          │              │
│  │  - Kafka Connect (datagen)  │  └──────────┬───────────────┘              │
│  │  - Control Center Next-Gen  │             │                              │
│  └─────────────────────────────┘             │                              │
│                                               │                              │
└───────────────────────────────────────────────┼──────────────────────────────┘
                                                │
                                                │
          ┌─────────────────────────────────────▼──────────────────────────┐
          │  WarpStream Cloud                   │    ADLS Gen2 Storage     │
          │                                     │                          │
          │  - Tableflow Cluster                │  - Storage Account       │
          │  - Agent Key                        │  - Filesystem (tableflow)│
          │  - REST Catalog                     │  - Iceberg Tables        │
          │    (metadata only)                  │                          │
          └─────────────────────────────────────┴──────────────────────────┘
```

### MinIO Backend with Trino

```text
┌──────────────────────────────────────────────────────────────────────────────┐
│                         Kubernetes Cluster                                   │
│                                                                              │
│  ┌─────────────────────────────┐  ┌──────────────────────────┐               │
│  │   Confluent Platform (CFK)  │  │   WarpStream Namespace   │               │
│  │                             │  │                          │               │
│  │  - KRaft Controller         │  │  - WarpStream Agent      │               │
│  │  - Kafka Broker             │  │  - MinIO Credentials     │               │
│  │  - Schema Registry          │  │                          │               │
│  │  - Kafka Connect (datagen)  │  └──────────┬───────────────┘               │
│  │  - Control Center Next-Gen  │             │                               │
│  └─────────────────────────────┘             │                               │
│                                               │                               │
│  ┌─────────────────────────────┐             │                               │
│  │   MinIO Namespace           │◄────────────┘                               │
│  │                             │                                              │
│  │  - MinIO Server             │◄─────────────┐                              │
│  │  - S3-compatible API        │              │                              │
│  │  - Tableflow Bucket         │              │                              │
│  │  - Iceberg Tables           │              │                              │
│  └─────────────────────────────┘              │                              │
│                                                │                              │
│  ┌─────────────────────────────┐              │                              │
│  │   Trino Namespace           │              │                              │
│  │                             │              │                              │
│  │  - Trino Query Engine       │──────────────┘                              │
│  │  - Iceberg Connector        │                                              │
│  │  - WarpStream Proxy         │─────────┐                                   │
│  └─────────────────────────────┘         │                                   │
│                                           │                                   │
└───────────────────────────────────────────┼───────────────────────────────────┘
                                            │
          ┌─────────────────────────────────▼─────┐
          │  WarpStream Cloud                     │
          │                                       │
          │  - Tableflow Cluster                  │
          │  - Agent Key                          │
          │  - REST Catalog (metadata only)       │
          └───────────────────────────────────────┘
```

## Project Structure

```text
warpstream-tableflow-demo/
├── .gitignore                         # Git ignore (Terraform state, secrets)
├── README.md                          # Main documentation
├── QUICK_START.md                     # 5-minute quick start guide
├── ARCHITECTURE.md                    # This file - detailed architecture
├── TROUBLESHOOTING.md                 # Troubleshooting guide
├── ADVANCED.md                        # Advanced queries and features
├── BACKEND_OPTIONS.md                 # Backend comparison (Azure vs MinIO)
├── demo-startup.sh                    # Main demo setup script
├── demo-cleanup.sh                    # Cleanup script
├── demo-query.sh                      # Unified query interface
├── scripts/
│   ├── common/                        # Shared utility functions
│   │   ├── colors.sh                  # Color definitions
│   │   ├── utils.sh                   # Utility functions
│   │   ├── azure.sh                   # Azure helpers
│   │   ├── terraform.sh               # Terraform helpers
│   │   ├── warpstream.sh              # WarpStream helpers
│   │   ├── kubernetes.sh              # Kubernetes helpers
│   │   └── port-forward.sh            # Port-forward management
│   ├── startup/                       # Startup step modules
│   │   ├── 01-cfk.sh                  # CFK operator installation
│   │   ├── 02-confluent.sh            # Confluent Platform deployment
│   │   ├── 03-datagen.sh              # Datagen connector
│   │   ├── 03b-minio.sh               # MinIO backend deployment
│   │   ├── 03c-trino.sh               # Trino query engine (MinIO backend)
│   │   ├── 04-terraform.sh            # Terraform resources
│   │   ├── 05-warpstream-agent.sh     # WarpStream agent
│   │   └── 06-tableflow-pipeline.sh   # Tableflow pipeline
│   ├── cleanup/                       # Cleanup step modules
│   │   ├── 01-credentials.sh
│   │   ├── 02-tableflow-pipeline.sh
│   │   ├── 03-warpstream-k8s.sh
│   │   ├── 03b-minio.sh               # MinIO cleanup
│   │   ├── 03c-trino.sh               # Trino cleanup
│   │   ├── 04-terraform.sh
│   │   ├── 05-confluent.sh
│   │   └── 06-cleanup-files.sh
│   └── trino-time-travel.sh           # Trino time travel query tool
└── environment/
    ├── azure/
    │   └── main.tf                    # Azure storage resources
    ├── minio/
    │   ├── README.md                  # MinIO documentation
    │   ├── namespace.yaml             # MinIO namespace
    │   ├── deployment.yaml            # MinIO server deployment
    │   ├── init-job.yaml              # MinIO bucket initialization
    │   └── deploy.sh                  # MinIO deployment script
    ├── trino/
    │   ├── k8s/
    │   │   ├── namespace.yaml         # Trino namespace
    │   │   ├── configmap.yaml         # Trino config (Azure - doesn't work)
    │   │   ├── configmap-minio.yaml   # Trino config (MinIO - works!)
    │   │   ├── deployment.yaml        # Trino deployment (Azure)
    │   │   ├── deployment-minio.yaml  # Trino deployment (MinIO)
    │   │   ├── service.yaml           # Trino service
    │   │   ├── proxy-configmap.yaml   # WarpStream auth proxy config
    │   │   ├── proxy-deployment.yaml  # Proxy deployment
    │   │   └── proxy-service.yaml     # Proxy service
    │   ├── deploy.sh                  # Deployment script (Azure)
    │   ├── deploy-minio.sh            # Deployment script (MinIO)
    │   ├── test.sh                    # Test script
    │   ├── README.md                  # Trino documentation (Azure)
    │   └── README-MINIO.md            # Trino documentation (MinIO)
    ├── confluent-platform/
    │   ├── cp.yaml                    # Confluent Platform CRs
    │   └── datagen-connector.yaml     # Datagen connector config
    └── warpstream/
        ├── agent/
        │   ├── warpstream-agent-template.yaml        # Azure backend template
        │   ├── warpstream-agent-minio-template.yaml  # MinIO backend template
        │   └── warpstream-agent.yaml                 # Generated config
        ├── cluster/
        │   └── main.tf                # WarpStream Tableflow cluster
        └── tableflow-pipeline/
            ├── main.tf                                      # Pipeline Terraform
            ├── orders-tableflow-pipeline-template.yaml      # Pipeline template
            └── orders-tableflow-pipeline.yaml               # Generated pipeline
```

## Data Flow

### 1. Data Generation
```
Kafka Connect (Datagen) → orders topic → Kafka Broker
```

### 2. Tableflow Transformation
```
WarpStream Agent → reads from Kafka
                 → transforms to Iceberg format
                 → writes to backend storage (Azure/MinIO)
```

### 3. Query Execution (MinIO only)
```
Trino → REST Catalog (metadata) → WarpStream Cloud
      → Data files (S3A)        → MinIO
```

## Component Responsibilities

| Component | Role |
|-----------|------|
| **Confluent Platform** | Message streaming and data generation |
| **WarpStream Agent** | Kafka protocol + Tableflow transformation |
| **WarpStream Cloud** | Iceberg REST catalog (metadata only) |
| **Backend Storage** | Iceberg data files (Parquet) |
| **Trino** | SQL query engine (MinIO only) |
| **Proxy** | Authentication for WarpStream REST catalog |

## Network Communication

**Ports:**
- Control Center: 9021 (port-forward)
- MinIO Console: 9001 (port-forward)
- MinIO API: 9000 (internal)
- Trino UI: 8080 (port-forward)
- Trino API: 8080 (internal)
- WarpStream Proxy: 8080 (internal)

**Internal DNS:**
- MinIO: `minio.minio.svc.cluster.local:9000`
- Trino: `trino.trino.svc.cluster.local:8080`
- Proxy: `warpstream-iceberg-proxy.trino.svc.cluster.local:8080`
- WarpStream REST: `https://metadata.default.<region>.azure.warpstream.com`

## See Also

- [README.md](README.md) - Main documentation
- [BACKEND_OPTIONS.md](BACKEND_OPTIONS.md) - Backend comparison
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - Troubleshooting guide
- [ADVANCED.md](ADVANCED.md) - Advanced queries
