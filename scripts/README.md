# Scripts

This folder contains modular components for the WarpStream Tableflow demo scripts.

## Structure

```
scripts/
├── README.md           # This file
├── common/             # Shared utility modules
│   ├── README.md
│   ├── colors.sh       # Terminal colors
│   ├── utils.sh        # General utilities
│   ├── azure.sh        # Azure authentication
│   ├── terraform.sh    # Terraform operations
│   ├── warpstream.sh   # WarpStream validation
│   └── kubernetes.sh   # Kubernetes helpers
├── startup/            # Demo startup modules
│   ├── README.md
│   ├── 01-cfk.sh
│   ├── 02-confluent.sh
│   ├── 03-datagen.sh
│   ├── 04-terraform.sh
│   ├── 05-warpstream-agent.sh
│   └── 06-tableflow-pipeline.sh
└── cleanup/            # Demo cleanup modules
    ├── README.md
    ├── 01-credentials.sh
    ├── 02-tableflow-pipeline.sh
    ├── 03-warpstream-k8s.sh
    ├── 04-terraform.sh
    ├── 05-confluent.sh
    └── 06-cleanup-files.sh
```

## Design Principles

1. **Modularity** - Each step is a separate file for easy maintenance
2. **Reusability** - Common functions are shared across scripts
3. **Ordering** - Numeric prefixes indicate execution order
4. **Documentation** - Each folder has its own README

## Main Scripts

The entry points are in the project root:
- `demo-startup.sh` - Sources and executes startup modules
- `demo-cleanup.sh` - Sources and executes cleanup modules

## Adding New Functionality

1. For shared utilities: Add to `common/`
2. For startup steps: Add to `startup/` with appropriate prefix
3. For cleanup steps: Add to `cleanup/` with appropriate prefix
4. Update the main script to source and call the new module
