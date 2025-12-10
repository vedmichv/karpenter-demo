# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Overview

This is a Karpenter demonstration repository for AWS EKS, showcasing autoscaling capabilities with Karpenter vs. Cluster Autoscaler. The repository contains Kubernetes manifests, installation scripts, and load testing tools for demonstrating Karpenter's node provisioning and consolidation features on AWS EKS.

## Environment Requirements

### Option 1: VSCode EC2 Instances (Recommended)
- Deploy 2 VSCode instances via CloudFormation (see vscode-instances/ directory)
- Fully automated setup with all tools pre-installed
- Ideal for demos requiring parallel monitoring and workload execution
- See vscode-instances/QUICKSTART.md for 5-minute deployment

### Option 2: AWS Cloud9
- Manual setup using cloud9-config.md instructions
- Requires manual tool installation

### Common Requirements
- kubectl, eksctl, helm, aws-cli v2
- Environment variables must be set before operations (see below)

## Essential Commands

### Required Environment Variables

Before running any commands, set these variables (typically in README.md):

```bash
export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.2.1"
export K8S_VERSION="1.32"
export CLUSTER_NAME="karpenter-demo-25-02-18-01"
export AWS_DEFAULT_REGION="eu-north-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
```

### Cluster Management

```bash
# Deploy EKS cluster with Karpenter (see README.md for full eksctl manifest)
eksctl create cluster -f <cluster-config>

# Scale managed nodegroup
eksctl scale nodegroup --cluster=${CLUSTER_NAME} --nodes=2 --name=${CLUSTER_NAME}-ng
```

### Karpenter Operations

```bash
# Install Karpenter via Helm
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=2 \
  --set controller.resources.requests.memory=2Gi \
  --set controller.resources.limits.cpu=4 \
  --set controller.resources.limits.memory=4Gi \
  --wait

# View Karpenter logs
kubectl logs -f -n "${KARPENTER_NAMESPACE}" -l app.kubernetes.io/name=karpenter -c controller

# Uninstall Karpenter
helm uninstall karpenter --namespace "${KARPENTER_NAMESPACE}"
```

### Load Testing

```bash
# High-load test: create 3000 pods in batches of 500
cd high-load/
./create.workload.sh 3000 500

# Delete batch workloads
./delete-workload.sh
```

### Monitoring

```bash
# Watch nodes with labels
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'

# Watch deployments
watch 'kubectl get deployment'

# Count deployments
watch 'kubectl get deployments.apps | grep -v NAME | wc -l'

# Check resource capacity (requires kubectl-krew plugin)
kubectl resource-capacity --sort cpu.request
```

### Dependencies

```bash
# Install metrics-server (required)
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Install kube-ops-view (required for demos)
cd kube-ops-view/
kubectl apply -k deploy
```

## Architecture

### Directory Structure

- **vscode-instances/**: CloudFormation infrastructure for VSCode EC2 instances
  - `cloudformation.yaml`: Main CloudFormation template for 2 VSCode instances
  - `deploy.sh`: Interactive deployment script
  - `status.sh`: Check stack and instance status
  - `delete-stack.sh`: Clean up all resources
  - `README.md`: Comprehensive documentation
  - `QUICKSTART.md`: 5-minute quick start guide

- **karpenter-demo01/**: Primary Karpenter demo manifests
  - `01-kr-start-10pods.yaml`: Initial 10-pod inflate deployment
  - `02-1-kr-demand-nodepool.yaml`: On-demand NodePool configuration
  - `02-2-kr-spot-nodepool.yaml`: Spot NodePool configuration
  - `02-3-nodeClass.yaml`: EC2NodeClass defining AMIs and subnets
  - `02-4-kr-600pods-splitload.yaml`: 600-pod split workload demo
  - `other-examples/`: Additional NodePool configurations

- **high-load/**: Load testing tools
  - `create.workload.sh`: Generates multiple deployments with random resource requests
  - `delete-workload.sh`: Cleans up batch workloads
  - `deployment-template.yaml`: Template for batch deployments

- **cluster-autoscaler/**: Cluster Autoscaler comparison manifests
  - NodeGroup configurations and test workloads

- **kube-ops-view/**: Kubernetes cluster visualization tool deployment

### Karpenter Resource Architecture

Karpenter uses two CRDs:
1. **NodePool** (karpenter.sh/v1): Defines node provisioning rules, capacity limits, and disruption policies
2. **EC2NodeClass** (karpenter.k8s.aws/v1): Defines AWS-specific configuration (AMIs, IAM roles, subnets, security groups)

Key NodePool features:
- **requirements**: Constraints for instance types, architectures, capacity types (spot/on-demand)
- **limits**: Maximum CPU/memory across all nodes
- **disruption.consolidationPolicy**: Controls when nodes are consolidated (WhenEmptyOrUnderutilized)
- **disruption.consolidateAfter**: Delay before consolidation (typically 1s for demos)
- **expireAfter**: Node lifecycle limit (720h = 30 days)

EC2NodeClass references are cluster-specific and must use:
- Role: `KarpenterNodeRole-${CLUSTER_NAME}`
- Subnet/SG tags: `karpenter.sh/discovery: ${CLUSTER_NAME}`

### Load Testing Architecture

The `create.workload.sh` script generates multiple Kubernetes Deployments with:
- Random CPU requests: 250m, 500m, 750m, 1, 2
- Random memory requests: 128M, 256M, 512M, 750M, 1G
- Configurable total pods and batch size
- Uses `pause` container (public.ecr.aws/eks-distro/kubernetes/pause:3.7) for minimal overhead

### Important Notes

- EC2NodeClass manifests contain hardcoded cluster names and AMI IDs that must be updated for new clusters
- The repository demonstrates both spot and on-demand instance provisioning
- High-load scenarios configure `kubelet.maxPods: 200` to support dense pod packing
- Managed nodegroups use `c5.2xlarge` instances to handle demo workloads
- Always run `helm registry logout public.ecr.aws` before Karpenter installation to avoid ECR auth issues
