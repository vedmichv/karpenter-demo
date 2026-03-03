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
./scripts/setup-all.sh 1.9.0        # With specific version
```

## What Gets Created

| Component | Basic Cluster (kd-basic-*) | Highload Cluster (kd-hl-*) |
|-----------|---------------------------|---------------------------|
| EKS version | 1.34 | 1.34 |
| Managed NodeGroup | c5.2xlarge, 2 nodes, tainted `CriticalAddonsOnly` | c5.2xlarge, 2 nodes, tainted `CriticalAddonsOnly` |
| Karpenter NodePool | spot + on-demand, cpu limit 5000 | spot only, cpu limit 5000 |
| EC2NodeClass | maxPods: default | maxPods: 200 (dense packing) |
| Monitoring | metrics-server + kube-ops-view | metrics-server + kube-ops-view |

Managed nodes have a `CriticalAddonsOnly` taint -- only Karpenter, kube-ops-view, and system pods run there. All workload pods trigger Karpenter to provision new nodes.

---

## Running the Demos (Step-by-Step)

After setup is complete you have two kubectl contexts: `kd-basic` and `kd-hl`. Below is a full walkthrough using two terminal windows.

### Step 0: Prepare two terminals

Open two terminal windows (or tabs). In each one, set up a separate kubeconfig so they don't interfere with each other:

**Terminal 1 (Basic cluster):**
```bash
aws eks update-kubeconfig --name kd-basic-YY-MM-DD --region eu-north-1 --kubeconfig ~/.kube/config-basic
export KUBECONFIG=~/.kube/config-basic

# Verify connection
kubectl get nodes
```

**Terminal 2 (Highload cluster):**
```bash
aws eks update-kubeconfig --name kd-hl-YY-MM-DD --region eu-north-1 --kubeconfig ~/.kube/config-highload
export KUBECONFIG=~/.kube/config-highload

# Verify connection
kubectl get nodes
```

> Replace `YY-MM-DD` with your cluster date (e.g., `26-03-02`).

Alternatively, use a single terminal and switch contexts:
```bash
kubectl config use-context kd-basic   # or kd-hl
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

### Step 2: Start watching nodes (keep running)

In each terminal, start a watch in a split pane or separate tab:

```bash
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'
```

You'll see the managed nodes (c5.2xlarge, no capacity-type label). As Karpenter provisions nodes, new rows will appear with `spot` or `on-demand` labels.

---

### Demo 1: Karpenter Basics (Terminal 1 -- kd-basic)

Shows: Karpenter provisioning nodes, scaling, and consolidation.

**a) Deploy 10 pods:**
```bash
kubectl apply -f manifests/basic/inflate-10pods.yaml
```
Watch kube-ops-view and the node watch -- Karpenter will provision a new node for these pods (managed nodes are tainted, so pods can't land there).

**b) Scale to 60 pods:**
```bash
kubectl scale --replicas=60 deployment/inflate
```
More nodes will appear as Karpenter provisions capacity.

**c) Scale down to 0 -- observe consolidation:**
```bash
kubectl scale --replicas=0 deployment/inflate
```
Watch Karpenter remove the now-empty nodes (consolidateAfter: 1s for fast demo).

**d) Clean up before next demo:**
```bash
kubectl delete deployment inflate
```

---

### Demo 2: Split Spot / On-Demand (Terminal 1 -- kd-basic)

Shows: Two separate NodePools with 50/50 topology spreading across spot and on-demand.

**a) Remove the simple NodePool:**
```bash
kubectl delete nodepools default
```

**b) Apply two separate NodePools (on-demand + spot):**
```bash
kubectl apply -f manifests/basic/nodepool-ondemand.yaml
kubectl apply -f manifests/basic/nodepool-spot.yaml
```

**c) Deploy 600 pods with topology spreading:**
```bash
kubectl apply -f manifests/basic/inflate-600pods-split.yaml
```

Watch the node list -- you'll see both `spot` and `on-demand` nodes appearing. The `topologySpreadConstraints` ensure roughly 50/50 distribution.

**d) Check the split:**
```bash
kubectl get nodes -L karpenter.sh/capacity-type --no-headers | awk '{print $6}' | sort | uniq -c
```

**e) Clean up:**
```bash
kubectl delete deployment inflate
kubectl delete nodepools on-demand spot
```

---

### Demo 3: High Load -- 3000 pods (Terminal 2 -- kd-hl)

Shows: Karpenter handling massive scale with spot instances and maxPods:200 per node.

**a) Launch 3000 pods in batches of 500:**
```bash
cd high-load
./create-workload.sh 3000 500
```

Each batch creates a Deployment with random CPU (250m-2) and memory (128M-1G) requests using `pause` containers. Watch nodes appear rapidly in kube-ops-view.

**b) Monitor progress:**
```bash
# How many deployments created
kubectl get deployments --no-headers | wc -l

# How many pods running vs pending
kubectl get pods --no-headers | awk '{print $3}' | sort | uniq -c
```

**c) Watch Karpenter logs (optional, in another pane):**
```bash
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```

**d) Clean up:**
```bash
./delete-workload.sh
cd ..
```
Watch Karpenter consolidate and remove all the now-empty nodes.

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
./scripts/teardown.sh kd-basic-YY-MM-DD kd-hl-YY-MM-DD
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
│   ├── lib.sh             # Shared functions (logging, config)
│   ├── check-prereqs.sh   # Verify tools installed
│   ├── get-latest-karpenter.sh  # Fetch version from GitHub
│   ├── create-cluster.sh  # Create one EKS cluster
│   ├── install-karpenter.sh    # Install Karpenter + manifests
│   ├── deploy-monitoring.sh    # metrics-server + kube-ops-view
│   ├── setup-contexts.sh  # Rename contexts to kd-basic/kd-hl
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
