# Karpenter Demo

Automated demo environment for AWS Karpenter autoscaler on EKS. Creates two clusters -- one for basic demos, one for high-load testing -- with full monitoring.

## Prerequisites

- AWS CLI v2 configured with appropriate permissions
- kubectl, eksctl, helm installed
- [eks-node-viewer](https://github.com/awslabs/eks-node-viewer) -- live terminal dashboard for node utilization and costs (`brew install eks-node-viewer`)
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
./scripts/setup-all.sh 1.9.0        # With specific version
```

## What Gets Created

| Component | Basic Cluster (k-basic-*) | Highload Cluster (k-hl-*) |
|-----------|---------------------------|---------------------------|
| EKS version | 1.35 | 1.35 |
| Managed NodeGroup | c5.2xlarge, 2 nodes, tainted `CriticalAddonsOnly` | c5.2xlarge, 2 nodes, tainted `CriticalAddonsOnly` |
| Karpenter NodePool | spot + on-demand, cpu limit 5000 | spot only, cpu limit 5000 |
| EC2NodeClass | maxPods: default | maxPods: 200 (dense packing) |
| Monitoring | metrics-server + kube-ops-view | metrics-server + kube-ops-view |

Managed nodes have a `CriticalAddonsOnly` taint -- only Karpenter, kube-ops-view, and system pods run there. All workload pods trigger Karpenter to provision new nodes.

---

## Running the Demos (Step-by-Step)

After setup is complete you have two kubectl contexts: `k-basic` and `k-hl`. Below is a full walkthrough using two terminal windows.

### Step 0: Prepare two terminals

Open two terminal windows (or tabs). In each one, set up a separate kubeconfig so they don't interfere with each other:

**Terminal 1 (Basic cluster):**
```bash
aws eks update-kubeconfig --name k-basic-26-03-10 --region eu-north-1 --kubeconfig ~/.kube/config-basic
export KUBECONFIG=~/.kube/config-basic

# Verify connection
kubectl get nodes
```

**Terminal 2 (Highload cluster):**
```bash
aws eks update-kubeconfig --name k-hl-26-03-10 --region eu-north-1 --kubeconfig ~/.kube/config-highload
export KUBECONFIG=~/.kube/config-highload

# Verify connection
kubectl get nodes
```

Alternatively, use a single terminal and switch contexts:
```bash
kubectl config use-context k-basic   # or k-hl
```

### Step 1: Open monitoring

Get kube-ops-view URL for each cluster:

**Terminal 1:**
```bash
echo "http://$(kubectl get svc kube-ops-view -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

**Terminal 2:**
```bash
echo "http://$(kubectl get svc kube-ops-view -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

Open both URLs in a browser. You'll see a live visual representation of nodes and pods.

### Step 2: Start monitoring panes (keep running)

For each terminal, open 3 extra panes/tabs and keep them running throughout the demos:

**Pane 1 -- Node watch:**
```bash
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'
```

**Pane 2 -- Karpenter logs (filtered: only node create/delete events):**
```bash
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller \
  | grep -E 'created nodeclaim|launched nodeclaim|registered nodeclaim|initialized nodeclaim|disrupting node|deleted node|deleted nodeclaim'
```

To see full unfiltered logs instead:
```bash
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```

**Pane 3 -- eks-node-viewer (live utilization, Karpenter nodes only):**
```bash
eks-node-viewer --node-selector karpenter.sh/nodepool --resources cpu,memory
```

You'll see the managed nodes in the node watch (c5.2xlarge, no capacity-type label). As Karpenter provisions nodes, new rows will appear with `spot` or `on-demand` labels. Karpenter logs will show every decision in real time. eks-node-viewer will show CPU/memory utilization filling up.

---

### Demo Guides

Detailed step-by-step guides with Karpenter log examples and what to tell the audience:

| Demo | Cluster | Guide |
|------|---------|-------|
| Karpenter Basics (10 pods, scale to 60, consolidation) + Split Spot/On-Demand 50/50 | k-basic (Terminal 1) | [docs/demo-basic.md](docs/demo-basic.md) |
| High Load -- 3000 pods with spot and maxPods:200 | k-hl (Terminal 2) | [docs/demo-highload.md](docs/demo-highload.md) |

---

## Useful Commands

```bash
# Karpenter controller logs (see provisioning decisions)
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller

# Resource usage per node
kubectl resource-capacity --sort cpu.request

# List Karpenter resources
kubectl get nodepools
kubectl get ec2nodeclasses

# Node details with labels
kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type

# Scale managed nodegroup (if needed)
eksctl scale nodegroup --cluster=CLUSTER_NAME --nodes=2 --name=CLUSTER_NAME-ng
```

## Monitoring

kube-ops-view is deployed on both clusters behind a LoadBalancer. Access is restricted by IP ranges configured in `manifests/monitoring/kube-ops-view/service.yaml` (`loadBalancerSourceRanges`).

To get the URL:
```bash
echo "http://$(kubectl get svc kube-ops-view -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

If you can't access the dashboard, check that your IP is in the allowed ranges and re-apply:
```bash
kubectl apply -k manifests/monitoring/kube-ops-view
```

## Teardown

### With Claude Code
```bash
/teardown-demo
```

### Standalone
```bash
./scripts/teardown.sh k-basic-26-03-10 k-hl-26-03-10
```

## Configuration

All defaults in `config.env`:

| Variable | Default | Description |
|----------|---------|-------------|
| AWS_DEFAULT_REGION | eu-north-1 | AWS region |
| K8S_VERSION | 1.35 | EKS Kubernetes version |
| MNG_INSTANCE_TYPE | c5.2xlarge | Managed nodegroup instance type |
| KARPENTER_VERSION_FALLBACK | 1.9.0 | Fallback if version detection fails |

Override any variable before running:
```bash
export K8S_VERSION="1.35"
./scripts/setup-all.sh
```

## Directory Structure

```
karpenter-demo/
├── scripts/          # Modular automation scripts
│   ├── lib.sh             # Shared functions (logging, config)
│   ├── check-prereqs.sh   # Verify tools installed
│   ├── get-latest-karpenter.sh  # Fetch version from GitHub
│   ├── create-cluster.sh  # Create one EKS cluster
│   ├── install-karpenter.sh    # Install Karpenter + manifests
│   ├── deploy-monitoring.sh    # metrics-server + kube-ops-view
│   ├── setup-contexts.sh  # Rename contexts to k-basic/k-hl
│   ├── setup-all.sh       # Master script (standalone)
│   └── teardown.sh        # Delete clusters with cleanup
├── manifests/
│   ├── basic/        # NodePools, EC2NodeClass, inflate deployments
│   ├── highload/     # Spot NodePool, dense packing (maxPods:200)
│   └── monitoring/   # kube-ops-view (kustomize)
├── high-load/        # Batch workload generation scripts
├── .claude/commands/ # /setup-demo and /teardown-demo
├── config.env        # Default configuration
└── README.md
```
