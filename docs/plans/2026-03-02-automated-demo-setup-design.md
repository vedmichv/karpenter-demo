# Automated Karpenter Demo Setup - Design Document

**Date:** 2026-03-02
**Status:** Approved

## Goal

Automate the full Karpenter demo setup: version check, two EKS clusters creation, Karpenter installation, monitoring deployment, and kubectl context configuration. Runnable via Claude Code `/setup-demo` command or standalone `./scripts/setup-all.sh`.

## Decisions

- **Approach:** Modular bash scripts + Claude Code custom commands
- **Environment:** Local Mac with aws-cli, kubectl, eksctl, helm
- **Region:** Always eu-north-1
- **Cluster names:** `kd-basic-YY-MM-DD` / `kd-hl-YY-MM-DD`
- **Old files:** Delete all, clean repo with new structure only
- **Karpenter configs:** basic starts simple (one NodePool), user manually evolves to split spot/on-demand. Highload: spot-only, maxPods:200

## Repository Structure

```
karpenter-demo/
├── scripts/
│   ├── lib.sh                    # Common functions: colors, logs, checks
│   ├── check-prereqs.sh          # Verify kubectl, eksctl, helm, aws-cli
│   ├── get-latest-karpenter.sh   # Parse karpenter.sh for latest version
│   ├── create-cluster.sh         # Create one EKS cluster (arg: basic|highload)
│   ├── install-karpenter.sh      # Install Karpenter on current context
│   ├── deploy-monitoring.sh      # Deploy metrics-server + kube-ops-view
│   ├── setup-contexts.sh         # Configure kubectl contexts with aliases
│   ├── setup-all.sh              # Master script: everything in one (no Claude)
│   └── teardown.sh               # Delete one or both clusters
│
├── manifests/
│   ├── basic/
│   │   ├── nodepool-simple.yaml       # Single NodePool (spot+on-demand)
│   │   ├── nodepool-ondemand.yaml     # Separate on-demand NodePool (split demo)
│   │   ├── nodepool-spot.yaml         # Separate spot NodePool (split demo)
│   │   ├── ec2nodeclass.yaml.tpl      # EC2NodeClass template (envsubst)
│   │   └── inflate-10pods.yaml        # Initial test deployment
│   │
│   ├── highload/
│   │   ├── nodepool-spot.yaml         # Spot NodePool with high limits
│   │   ├── ec2nodeclass.yaml.tpl      # Template with maxPods: 200
│   │   └── deployment-template.yaml   # Template for batch deployments
│   │
│   └── monitoring/
│       └── kube-ops-view/             # kustomize deployment
│           ├── kustomization.yaml
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── redis-deployment.yaml
│           ├── redis-service.yaml
│           └── rbac.yaml
│
├── high-load/
│   ├── create-workload.sh
│   └── delete-workload.sh
│
├── .claude/commands/
│   ├── setup-demo.md              # /setup-demo orchestration
│   └── teardown-demo.md           # /teardown-demo cleanup
│
├── config.env                     # Default values
├── CLAUDE.md
└── README.md
```

## Automation Flow

### `/setup-demo` (Claude Code command)

1. Check prerequisites (kubectl, eksctl, helm, aws-cli, AWS credentials)
2. WebFetch karpenter.sh -> get latest Karpenter version
3. Ask user: "Latest version X.Y.Z, use it?"
4. Generate cluster names: kd-basic-YY-MM-DD / kd-hl-YY-MM-DD
5. Create both clusters (via scripts/create-cluster.sh)
6. Install Karpenter on both clusters
7. Deploy NodePools + EC2NodeClass:
   - basic: simple NodePool (one, spot+on-demand)
   - highload: spot-only NodePool with maxPods:200
8. Deploy metrics-server + kube-ops-view on both
9. Configure kubectl contexts: kd-basic / kd-hl
10. Show summary: contexts, kube-ops-view URLs, switch commands

### `./scripts/setup-all.sh` (standalone)

Same flow without interactivity. Gets version from config.env or karpenter.sh via curl.

## config.env

```bash
AWS_DEFAULT_REGION="eu-north-1"
K8S_VERSION="1.34"
CLUSTER_PREFIX="kd"
BASIC_CLUSTER_SUFFIX="basic"
HIGHLOAD_CLUSTER_SUFFIX="hl"
MNG_INSTANCE_TYPE="c5.2xlarge"
MNG_MIN_SIZE=1
MNG_MAX_SIZE=10
MNG_DESIRED_SIZE=2
KARPENTER_VERSION_FALLBACK="1.8.2"
KARPENTER_NAMESPACE="kube-system"
```

## Manifest Templates

EC2NodeClass and cluster-specific manifests use `.yaml.tpl` with envsubst variables:
- `${CLUSTER_NAME}` - cluster name
- `${ALIAS_VERSION}` - AMI alias version

No hardcoded AMI IDs or cluster names.

## Kubectl Contexts

After cluster creation, rename long eksctl contexts to short aliases:
- `kd-basic` -> basic cluster
- `kd-hl` -> highload cluster
