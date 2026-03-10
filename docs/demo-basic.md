# Demo: Karpenter Basics + Split Spot/On-Demand (k-basic cluster)

**Cluster:** k-basic (Terminal 1)
**What we show:** Karpenter provisioning, scaling, consolidation, and 50/50 spot/on-demand split.

---

## Preparation

Make sure monitoring is running in separate panes/tabs:

**Pane 1 -- Node watch:**
```bash
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'
```

**Pane 2 -- Karpenter logs (filtered: only node create/delete events):**
```bash
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller \
  | grep -E 'computed new|created nodeclaim|launched nodeclaim|registered nodeclaim|initialized nodeclaim|disrupting node|deleted node|deleted nodeclaim'
```

Full unfiltered logs (alternative):
```bash
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```

**Pane 3 -- eks-node-viewer (live utilization, Karpenter nodes only):**
```bash
eks-node-viewer --node-selector karpenter.sh/nodepool --resources cpu,memory
```

**Browser:** open kube-ops-view URL:
```bash
echo "http://$(kubectl get svc kube-ops-view -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
```

---

## Part 1: Provisioning and Consolidation

### Step 1: Deploy 10 pods

```bash
kubectl apply -f manifests/basic/inflate-10pods.yaml
```

Walk through the Karpenter logs -- 4 events happen in sequence:

**1. "computed new nodeclaim(s) to fit pod(s)"** -- Karpenter sees 10 pending pods, calculates how many nodes it needs:
```
"computed new nodeclaim(s) to fit pod(s)"  nodeclaims: 1, pods: 10
```

**2. "created nodeclaim"** -- Creates a NodeClaim. Shows total resources requested and how many instance types were available from EC2 API:
```
"created nodeclaim"  requests: {cpu: 2850m, memory: 2816Mi, pods: 14}
                     instance-types: c5.12xlarge, c5.18xlarge, c5.2xlarge, m5.xlarge ... and 299 other(s)
```
> Tell the audience: Karpenter queried the EC2 API, got 300+ available instance types that match our NodePool constraints, and will pick the cheapest one that fits all 10 pods.

**3. "launched nodeclaim"** -- EC2 instance is running. Shows exactly what was selected:
```
"launched nodeclaim"  instance-type: m5.xlarge, zone: eu-north-1b, capacity-type: spot
                      allocatable: {cpu: 3920m, memory: 14162Mi, pods: 58}
```
> Tell the audience: Karpenter chose a spot m5.xlarge -- the cheapest option that fits the 2850m CPU request. It also shows what the node can allocate: ~4 CPU, ~14Gi memory, up to 58 pods.

**4. "initialized nodeclaim"** -- Node joined the cluster, pods are scheduling:
```
"initialized nodeclaim"  Node: ip-192-168-xxx-xx.eu-north-1.compute.internal
```

Now verify -- show pods running on the new Karpenter node:
```bash
kubectl get pods -o wide
kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type
```
> Point out: the managed c5.2xlarge nodes have no capacity-type label and no workload pods (they're tainted). The new m5.xlarge has `spot` label and all 10 inflate pods.

### Step 2: Scale to 60 pods

```bash
kubectl scale --replicas=60 deployment/inflate
```

In the logs you'll see multiple "computed" + "created" + "launched" events -- Karpenter provisions several nodes in parallel. Each log line shows the instance type, availability zone, and capacity type it picked.

Watch eks-node-viewer -- CPU/memory bars fill up across new nodes in real time.

Check the result:
```bash
kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type
```
> Point out: multiple Karpenter nodes appeared, possibly different instance types. Karpenter bin-packs efficiently -- it doesn't just pick one size, it picks the best fit for the remaining pods.

### Step 3: Scale down to 0 -- observe consolidation

```bash
kubectl scale --replicas=0 deployment/inflate
```

Watch the logs -- consolidation events:

**1. "disrupting node(s)"** -- Karpenter identifies empty nodes to remove:
```
"disrupting node(s)"  command: Empty, decision: delete, disrupted-node-count: 1 (savings: $0.06)
```
> Tell the audience: Karpenter calculates the cost savings for each node removal. `consolidateAfter: 1s` means it acts within 1 second of detecting an empty node.

**2. "deleted node" / "deleted nodeclaim"** -- node terminated in AWS:
```
"deleted node"       ip-192-168-xxx-xx.eu-north-1.compute.internal
"deleted nodeclaim"  provider-id: aws:///eu-north-1b/i-xxxxx
```

Watch nodes vanish in kube-ops-view and eks-node-viewer. Within seconds all Karpenter nodes are gone.

### Step 4: Clean up

```bash
kubectl delete deployment inflate
```

---

## Part 2: Split Spot / On-Demand (50/50)

> Tell the audience: Now we'll show how to run half the workload on spot instances (cheap but can be interrupted) and half on on-demand (stable, more expensive). Karpenter makes this trivial with topology spreading.

### Step 1: Remove the simple NodePool, apply spot + on-demand

```bash
kubectl delete nodepools default
```

Apply two separate NodePools -- each handles one capacity type:
```bash
kubectl apply -f manifests/basic/nodepool-ondemand.yaml
kubectl apply -f manifests/basic/nodepool-spot.yaml
```

> Point out: the on-demand NodePool has `capacity-spread: ["1", "2"]` and the spot NodePool has `capacity-spread: ["3", "4"]`. This is a custom label used for topology spreading.

Verify:
```bash
kubectl get nodepools
```

### Step 2: Deploy 600 pods with topology spreading

```bash
kubectl apply -f manifests/basic/inflate-600pods-split.yaml
```

In the logs you'll see nodeclaims from both NodePools being created simultaneously -- some with `capacity-type: spot`, others with `capacity-type: on-demand`.

Watch kube-ops-view and eks-node-viewer -- you'll see both types of nodes appearing and filling up.

### Step 3: Verify the 50/50 split

```bash
kubectl get nodes -L karpenter.sh/capacity-type --no-headers | awk '{print $6}' | sort | uniq -c
```

Expected output -- roughly equal numbers of spot and on-demand nodes:
```
  5 on-demand
  5 spot
```

> Tell the audience: The `topologySpreadConstraints` with `maxSkew: 1` ensures pods are evenly distributed across the capacity-spread values. Since on-demand has values 1,2 and spot has 3,4 -- pods spread ~50/50.

Also check in eks-node-viewer -- you'll see both spot and on-demand nodes with their utilization.

### Step 4: Clean up

```bash
kubectl delete deployment inflate
kubectl delete nodepools on-demand spot
```

Watch all nodes consolidate and disappear.
