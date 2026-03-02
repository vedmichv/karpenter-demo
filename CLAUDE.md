# CLAUDE.md

This file provides guidance to Claude Code when working with this repository.

## Repository Overview

Karpenter demo repository for AWS EKS. Automates creation of two EKS clusters (basic + highload) with Karpenter autoscaler, monitoring, and kubectl context setup.

## Quick Start

### With Claude Code
```bash
/setup-demo    # Interactive: checks version, creates clusters, installs everything
/teardown-demo # Interactive: finds and deletes demo clusters
```

### Without Claude Code
```bash
./scripts/setup-all.sh           # Full automated setup
./scripts/setup-all.sh 1.8.2     # With specific Karpenter version
./scripts/teardown.sh kd-basic-26-03-02 kd-hl-26-03-02
```

## Architecture

### Two-Cluster Setup

| Cluster | Name Pattern | Purpose | Karpenter Config |
|---------|-------------|---------|-----------------|
| Basic | kd-basic-YY-MM-DD | Demo basics, consolidation, split spot/on-demand | Simple NodePool (spot+on-demand), maxPods default |
| Highload | kd-hl-YY-MM-DD | 3000+ pod load testing | Spot-only NodePool, maxPods: 200 |

### Directory Structure

- **scripts/**: Modular bash scripts for each operation
  - `lib.sh` - Shared functions (logging, config, cluster name generation)
  - `check-prereqs.sh` - Verify tools (kubectl, eksctl, helm, aws-cli)
  - `get-latest-karpenter.sh` - Fetch latest version from GitHub/Helm
  - `create-cluster.sh` - Create one EKS cluster (CloudFormation + eksctl)
  - `install-karpenter.sh` - Install Karpenter + apply manifests
  - `deploy-monitoring.sh` - Deploy metrics-server + kube-ops-view
  - `setup-contexts.sh` - Rename kubectl contexts to kd-basic/kd-hl
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

Key defaults: region=eu-north-1, K8s=1.34, instance=c5.2xlarge, Karpenter fallback=1.8.2

## Demo Flows

### Demo 1: Basic Karpenter (kd-basic cluster)
```bash
kubectl config use-context kd-basic
kubectl apply -f manifests/basic/inflate-10pods.yaml    # 10 pods -> Karpenter provisions nodes
kubectl scale --replicas=60 deployment/inflate           # Scale up -> more nodes
kubectl scale --replicas=0 deployment/inflate            # Scale down -> consolidation
```

### Demo 2: Split Spot/On-Demand (kd-basic cluster)
```bash
kubectl delete nodepools default                         # Remove simple NodePool
kubectl apply -f manifests/basic/nodepool-ondemand.yaml  # On-demand NodePool
kubectl apply -f manifests/basic/nodepool-spot.yaml      # Spot NodePool
kubectl apply -f manifests/basic/inflate-600pods-split.yaml  # 600 pods with topology spreading
```

### Demo 3: High Load (kd-hl cluster)
```bash
kubectl config use-context kd-hl
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
kubectl config use-context kd-basic   # Basic cluster
kubectl config use-context kd-hl      # Highload cluster

# Or separate kubeconfigs per terminal:
export KUBECONFIG=~/.kube/config-basic     # Terminal 1
export KUBECONFIG=~/.kube/config-highload  # Terminal 2
```
