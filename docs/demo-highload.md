# Demo: High Load -- 3000+ Pods (k-hl cluster)

**Cluster:** k-hl (Terminal 2)
**What we show:** Karpenter handling massive scale with spot instances, maxPods:200 per node, and restricted instance families (c5/c6i/c7i, m5/m6i/m7i, r5/r6i/r7i).

---

## Preparation

Make sure monitoring is running in separate panes/tabs:

**Pane 1 -- Node watch:**
```bash
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'
```

**Pane 2 -- Karpenter logs (filtered):**
```bash
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller \
  | grep -E 'computed new|created nodeclaim|launched nodeclaim|registered nodeclaim|initialized nodeclaim|disrupting node|deleted node|deleted nodeclaim'
```

**Pane 3 -- eks-node-viewer (Karpenter nodes only):**
```bash
eks-node-viewer --node-selector karpenter.sh/nodepool --resources cpu,memory
```

**Browser:** open kube-ops-view URL:
```bash
echo "http://$(kubectl get svc kube-ops-view -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

---

## What's different on this cluster

Before starting, show the audience the NodePool and EC2NodeClass config:

```bash
kubectl get nodepool default -o yaml | grep -A 20 requirements
```

> Point out key differences from the basic cluster:
> - **Spot only** -- all nodes are spot instances for maximum cost savings
> - **Instance families restricted** -- only c5/c6i/c7i, m5/m6i/m7i, r5/r6i/r7i (no GPU, no storage-optimized, no exotic types)
> - **No metal instances** -- excluded to avoid long boot times

```bash
kubectl get ec2nodeclass default -o yaml | grep -A 3 kubelet
```

> Point out: **maxPods: 200** -- normally a node runs ~30-60 pods. We're allowing up to 200 pods per node for dense packing. This means fewer nodes needed = lower cost.

---

## Step 1: Launch 3000 pods

```bash
cd high-load
./create-workload.sh 3000 500
```

The script creates Deployments in batches of 500 pods. Each batch has random CPU (250m-2 cores) and memory (128M-1G) requests using `pause` containers.

Watch the logs -- you'll see a rapid sequence of "computed" + "created" + "launched" events. Karpenter provisions many nodes simultaneously.

> Tell the audience: Each "launched nodeclaim" shows the instance type Karpenter picked. Notice they're all from our allowed families (c5, c6i, m5, m6i, etc.) -- no exotic instances. And they're all spot.

Watch eks-node-viewer -- nodes appear and quickly fill up. With maxPods:200, each node handles far more pods than usual.

## Step 2: Monitor the result

```bash
# How many deployments
kubectl get deployments --no-headers | wc -l

# Pod status breakdown
kubectl get pods --no-headers | awk '{print $3}' | sort | uniq -c

# Node count and types
kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type --no-headers | grep spot | wc -l
```

> Point out in eks-node-viewer:
> - How many nodes Karpenter created
> - CPU/memory utilization per node (should be high -- efficient bin packing)
> - All nodes show "spot" capacity type
> - Instance types are from the allowed families only

## Step 3: Clean up -- observe massive consolidation

```bash
./delete-workload.sh
cd ..
```

Watch the logs -- Karpenter detects all nodes are now empty and removes them:
```
"disrupting node(s)"  command: Empty, decision: delete, disrupted-node-count: 1 (savings: $X.XX)
```

> Tell the audience: All spot nodes are terminated within seconds. The cost savings are shown per node. This is the power of Karpenter + spot -- you only pay for what you use, and cleanup is automatic.

Watch eks-node-viewer and kube-ops-view -- all Karpenter nodes disappear, only the managed c5.2xlarge nodes remain with system pods.
