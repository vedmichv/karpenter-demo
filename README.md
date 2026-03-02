# Karpenter Demo

Automated demo environment for AWS Karpenter autoscaler on EKS. Creates two clusters -- one for basic demos, one for high-load testing -- with full monitoring.

## Prerequisites

- AWS CLI v2 configured with appropriate permissions
- kubectl, eksctl, helm installed
- macOS or Linux

## Quick Start

### Option 1: Claude Code (interactive)

```bash
/setup-demo
```

Claude will check the latest Karpenter version, create both clusters, install Karpenter, deploy monitoring, and set up kubectl contexts.

### Option 2: Standalone script

```bash
./scripts/setup-all.sh              # Auto-detect latest Karpenter version
./scripts/setup-all.sh 1.8.2        # Use specific version
```

## What Gets Created

| Component | Basic Cluster (kd-basic-*) | Highload Cluster (kd-hl-*) |
|-----------|---------------------------|---------------------------|
| EKS version | 1.34 | 1.34 |
| Managed NodeGroup | c5.2xlarge (2-10 nodes) | c5.2xlarge (2-10 nodes) |
| Karpenter NodePool | spot + on-demand | spot only |
| maxPods | default | 200 (dense packing) |
| CPU limit | 5000 | 5000 |
| Monitoring | metrics-server + kube-ops-view | metrics-server + kube-ops-view |

## Switching Between Clusters

```bash
kubectl config use-context kd-basic   # Basic cluster
kubectl config use-context kd-hl      # Highload cluster
```

Or use separate terminal sessions:
```bash
# Terminal 1
export KUBECONFIG=~/.kube/config-basic

# Terminal 2
export KUBECONFIG=~/.kube/config-highload
```

## Demo Scenarios

### Demo 1: Karpenter Basics

```bash
kubectl config use-context kd-basic

# Deploy 10 pods -- watch Karpenter provision nodes
kubectl apply -f manifests/basic/inflate-10pods.yaml

# Scale to 60 -- more nodes added
kubectl scale --replicas=60 deployment/inflate

# Scale to 0 -- watch consolidation
kubectl scale --replicas=0 deployment/inflate
```

### Demo 2: Split Spot / On-Demand

```bash
kubectl config use-context kd-basic

# Replace simple NodePool with split configuration
kubectl delete nodepools default
kubectl apply -f manifests/basic/nodepool-ondemand.yaml
kubectl apply -f manifests/basic/nodepool-spot.yaml

# Deploy 600 pods with topology spreading (50/50 spot/on-demand)
kubectl apply -f manifests/basic/inflate-600pods-split.yaml
```

### Demo 3: High Load (3000+ pods)

```bash
kubectl config use-context kd-hl

# Create 3000 pods in batches of 500 with random resource requests
cd high-load
./create-workload.sh 3000 500

# Clean up
./delete-workload.sh
```

## Monitoring

kube-ops-view is deployed on both clusters with a LoadBalancer:
```bash
kubectl get svc kube-ops-view -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

Other useful commands:
```bash
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
kubectl resource-capacity --sort cpu.request
```

## Teardown

### With Claude Code
```bash
/teardown-demo
```

### Standalone
```bash
./scripts/teardown.sh kd-basic-26-03-02 kd-hl-26-03-02
```

## Configuration

All defaults in `config.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| AWS_DEFAULT_REGION | eu-north-1 | AWS region |
| K8S_VERSION | 1.34 | EKS Kubernetes version |
| MNG_INSTANCE_TYPE | c5.2xlarge | Managed nodegroup instance type |
| KARPENTER_VERSION_FALLBACK | 1.8.2 | Fallback if version detection fails |

Override any variable before running:
```bash
export K8S_VERSION="1.35"
./scripts/setup-all.sh
```

## Directory Structure

```
karpenter-demo/
├── scripts/          # Modular automation scripts
├── manifests/
│   ├── basic/        # NodePools, EC2NodeClass, inflate deployments
│   ├── highload/     # Spot NodePool, dense packing config
│   └── monitoring/   # kube-ops-view (kustomize)
├── high-load/        # Batch workload generation scripts
├── .claude/commands/ # Claude Code custom commands
├── config.env        # Default configuration
└── README.md
```
