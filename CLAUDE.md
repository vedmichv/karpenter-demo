# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Repository Overview

Karpenter demo repository for AWS EKS. Automates creation of two EKS clusters (basic + highload) with Karpenter autoscaler, monitoring, and kubectl context setup.

## AWS Preflight (check BEFORE any aws/eksctl command)

The clusters live in ONE specific AWS account, profile, and region. The shell's
`[default]` profile and default region often point somewhere else, so always
confirm context first — otherwise `aws` commands silently target the wrong account.

```bash
# 1. Which account/identity am I actually using?
aws sts get-caller-identity --query 'Account' --output text

# 2. Is the right profile/region active?
echo "profile=${AWS_PROFILE:-default} region=$(aws configure get region)"

# 3. Sanity check: can I see the demo clusters?
aws eks list-clusters --region eu-north-1
```

If the account is wrong or clusters don't appear:

- **Select the correct profile:** `export AWS_PROFILE=<demo-profile>` (the
  isengardcli profile tied to the demo account — see private memory for the exact
  name, account ID, and region; not committed here because this repo is public).
- **Unset overriding creds:** if `AWS_BEARER_TOKEN` is set in the environment it
  OVERRIDES profile credentials — `unset AWS_BEARER_TOKEN` before relying on the
  profile.
- **Set the region explicitly:** `export AWS_DEFAULT_REGION=eu-north-1` (shell
  default is frequently `us-east-1`).

**Tell-tale symptom of wrong account:** `aws eks list-clusters` /
`describe-load-balancers` return empty, yet `kubectl` still works fine (kubeconfig
uses its own saved token, independent of the active AWS profile). Empty AWS output
≠ resources gone — verify the account first.

## Quick Start

### With Claude Code
```bash
/setup-demo    # Interactive: checks version, creates clusters, installs everything
/teardown-demo # Interactive: finds and deletes demo clusters
```

### Without Claude Code
```bash
./scripts/setup-all.sh           # Full automated setup
./scripts/setup-all.sh 1.9.0     # With specific Karpenter version
./scripts/teardown.sh k-basic-26-03-10 k-hl-26-03-10
```

## Architecture

### Two-Cluster Setup

| Cluster | Name Pattern | Purpose | Karpenter Config |
|---------|-------------|---------|-----------------|
| Basic | k-basic-YY-MM-DD | Demo basics, consolidation, split spot/on-demand | Simple NodePool (spot+on-demand), maxPods default |
| Highload | k-hl-YY-MM-DD | 3000+ pod load testing | Spot-only NodePool, maxPods: 200 |

### Directory Structure

- **scripts/**: Modular bash scripts for each operation
  - `lib.sh` - Shared functions (logging, config, cluster name generation)
  - `check-prereqs.sh` - Verify tools (kubectl, eksctl, helm, aws-cli)
  - `get-latest-karpenter.sh` - Fetch latest version from GitHub/Helm
  - `create-cluster.sh` - Create one EKS cluster (CloudFormation + eksctl)
  - `install-karpenter.sh` - Install Karpenter + apply manifests
  - `deploy-monitoring.sh` - Deploy metrics-server + kube-ops-view
  - `setup-contexts.sh` - Rename kubectl contexts to k-basic/k-hl
  - `setup-all.sh` - Master orchestrator (standalone, no Claude needed)
  - `teardown.sh` - Delete one or both clusters with full cleanup

- **manifests/**: Kubernetes manifests
  - `basic/` - NodePools (simple, on-demand, spot), EC2NodeClass template, inflate deployments
  - `highload/` - Spot NodePool, EC2NodeClass with maxPods:200, deployment template
  - `monitoring/kube-ops-view/` - Kustomize deployment for cluster visualization

- **high-load/**: Load testing scripts
  - `create-workload.sh` - Generate batch deployments with random resources
  - `delete-workload.sh` - Clean up batch deployments

- **config.env**: Default configuration (region, K8s version, instance types, etc.)

- **.claude/commands/**: Claude Code custom commands
  - `setup-demo.md` - Interactive setup orchestration
  - `teardown-demo.md` - Interactive teardown

## Configuration

All defaults in `config.env`. Override by exporting before running:
```bash
export K8S_VERSION="1.35"   # Override K8s version
./scripts/setup-all.sh       # Will use 1.35
```

Key defaults: region=eu-north-1, K8s=1.35, instance=c5.2xlarge, Karpenter fallback=1.9.0

## Demo Flows

### Demo 1: Basic Karpenter (k-basic cluster)
```bash
kubectl config use-context k-basic
kubectl apply -f manifests/basic/inflate-10pods.yaml    # 10 pods -> Karpenter provisions nodes
kubectl scale --replicas=60 deployment/inflate           # Scale up -> more nodes
kubectl scale --replicas=0 deployment/inflate            # Scale down -> consolidation
```

### Demo 2: Split Spot/On-Demand (k-basic cluster)
```bash
kubectl delete nodepools default                         # Remove simple NodePool
kubectl apply -f manifests/basic/nodepool-ondemand.yaml  # On-demand NodePool
kubectl apply -f manifests/basic/nodepool-spot.yaml      # Spot NodePool
kubectl apply -f manifests/basic/inflate-600pods-split.yaml  # 600 pods with topology spreading
```

### Demo 3: High Load (k-hl cluster)
```bash
kubectl config use-context k-hl
cd high-load && ./create-workload.sh 3000 500    # 3000 pods, batches of 500
./delete-workload.sh                              # Clean up
```

## Essential Monitoring Commands

```bash
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
kubectl resource-capacity --sort cpu.request
```

## Manifest Templates

EC2NodeClass files use `.yaml.tpl` extension with envsubst variables:
- `${CLUSTER_NAME}` - EKS cluster name
- `${ALIAS_VERSION}` - AMI alias version (auto-discovered)

No hardcoded AMI IDs or cluster names in any manifest.

## Context Switching

```bash
kubectl config use-context k-basic   # Basic cluster
kubectl config use-context k-hl      # Highload cluster

# Or separate kubeconfigs per terminal:
export KUBECONFIG=~/.kube/config-basic     # Terminal 1
export KUBECONFIG=~/.kube/config-highload  # Terminal 2
```
