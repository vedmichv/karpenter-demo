# Karpenter Community Analysis: Issues, Questions & Solutions (2023-2025)

**Analysis Period:** January 2023 - December 2025
**Repositories:**
- [aws/karpenter-provider-aws](https://github.com/aws/karpenter-provider-aws)
- [kubernetes-sigs/karpenter](https://github.com/kubernetes-sigs/karpenter)

**Total Open Issues (aws/karpenter-provider-aws):** 393
**Analysis Date:** December 10, 2025

---

## Quick Reference Links

### Official Resources
- 📖 [Karpenter Documentation](https://karpenter.sh/)
- 🐛 [Report Issues (AWS Provider)](https://github.com/aws/karpenter-provider-aws/issues)
- 🐛 [Report Issues (Core)](https://github.com/kubernetes-sigs/karpenter/issues)
- 📦 [Release Notes (AWS Provider)](https://github.com/aws/karpenter-provider-aws/releases)
- 📦 [Release Notes (Core)](https://github.com/kubernetes-sigs/karpenter/releases)
- 🔄 [Migration Guide](https://karpenter.sh/docs/upgrading/upgrade-guide/)
- 💬 [Kubernetes Slack #karpenter](https://kubernetes.slack.com/archives/C02SFFZSA2K)

### Repository Quick Links
- [All Open Issues (AWS Provider)](https://github.com/aws/karpenter-provider-aws/issues?q=is%3Aissue+is%3Aopen)
- [Issues by Most Reactions](https://github.com/aws/karpenter-provider-aws/issues?q=is%3Aissue+is%3Aopen+sort%3Areactions-%2B1-desc)
- [Issues by Most Comments](https://github.com/aws/karpenter-provider-aws/issues?q=is%3Aissue+is%3Aopen+sort%3Acomments-desc)
- [Recent Releases](https://github.com/aws/karpenter-provider-aws/releases)

---

## Table of Contents

1. [Most Common Issues & Questions](#1-most-common-issues--questions)
   - [Consolidation & Node Churn](#11-consolidation--node-churn-critical-production-impact)
   - [Migration from Cluster Autoscaler](#12-migration-from-cluster-autoscaler)
   - [v1.0 Migration Challenges](#13-v10-migration-challenges)
   - [Node Lifecycle & NotReady Nodes](#14-node-lifecycle--notready-nodes)
   - [Subnet & Network Resource Exhaustion](#15-subnet--network-resource-exhaustion)
   - [Spot Instance & Interruption Handling](#16-spot-instance--interruption-handling)
   - [Disruption Control Issues](#17-disruption-control-issues)
2. [Top Feature Requests](#2-top-feature-requests-by-community-demand)
3. [**Karpenter Deployment Strategies & Limitations**](#3-karpenter-deployment-strategies--limitations) ⭐ NEW
   - [Where to Run Karpenter Controller](#31-where-to-run-karpenter-controller)
   - [Managed Node Group Deployment](#32-managed-node-group-deployment-recommended)
   - [Fargate Deployment](#33-fargate-deployment)
   - [The Circular Dependency Problem](#34-the-circular-dependency-problem)
   - [Deployment Strategy Decision Tree](#35-deployment-strategy-decision-tree)
4. [Most Common Configuration Mistakes](#4-most-common-configuration-mistakes)
5. [Common Error Messages & Solutions](#5-common-error-messages--solutions)
6. [Version-Specific Issues & Migration Guides](#6-version-specific-issues--migration-guides)
7. [Best Practices & Recommendations](#7-best-practices--recommendations)
8. [Troubleshooting Playbook](#8-troubleshooting-playbook)
9. [Advanced Configurations](#9-advanced-configurations)
10. [Known Bugs & Workarounds](#10-known-bugs--workarounds-current)
11. [Community Resources & Support](#11-community-resources--support)
12. [Migration Decision Matrix](#12-migration-decision-matrix)
13. [Top 20 Issues by Community Impact](#13-top-20-issues-by-community-impact)
14. [Key Takeaways & Recommendations](#14-key-takeaways--recommendations)
15. [Upcoming Features to Watch](#15-upcoming-features-to-watch)
16. [Breaking Changes History](#16-breaking-changes-history)

---

## Executive Summary

This analysis reviews 2+ years of Karpenter GitHub issues, release notes, and community discussions to identify the most common problems, questions, and solutions. The findings reveal that while Karpenter has matured significantly, users consistently face challenges around:

1. **Consolidation behavior** causing excessive node churn
2. **Migration complexity** from Cluster Autoscaler and v0.x to v1.x
3. **Webhook configuration** issues, especially with GitOps tools
4. **Node lifecycle management** (NotReady nodes, stuck NodeClaims)
5. **Resource exhaustion** (subnet IPs, storage limits)

---

## 1. Most Common Issues & Questions

### 1.1 Consolidation & Node Churn (Critical Production Impact)

#### [Issue #7146](https://github.com/aws/karpenter-provider-aws/issues/7146): Excessive "Underutilized" Node Churn
**Reactions:** 54 👍 | **Comments:** 37 | **Status:** Open
**Impact:** HIGH - Production disruption
**Link:** https://github.com/aws/karpenter-provider-aws/issues/7146

**Problem:**
- Karpenter enters periods of high node volatility (30+ minute windows)
- Nodes are repeatedly disrupted and replaced as "Underutilized"
- Newly created nodes are disrupted again 5-10 minutes after creation
- Can affect up to 50% of nodes (matching disruption budget)
- Typically occurs during low-traffic periods

**Common Symptoms:**
```
Event: "Unconsolidatable - Can't remove without creating 2 candidates"
- Consolidation creates worse topology than starting configuration
- Pods restarted multiple times in rapid succession
```

**Resolution Status:** Under investigation by maintainers

**Workarounds:**
1. Increase `consolidateAfter` from default (e.g., 5m instead of 1s)
2. Lower disruption budget percentage
3. Use time-based disruption budgets for specific windows
4. Add `karpenter.sh/do-not-disrupt: "true"` annotation during critical hours

**Related Issues:**
- [#3773](https://github.com/aws/karpenter-provider-aws/issues/3773) - Slow event handlers blocking queue (7 reactions)
- [kubernetes-sigs/karpenter#651](https://github.com/kubernetes-sigs/karpenter/issues/651) - Taint nodes before consolidation validation (74 reactions)
- [kubernetes-sigs/karpenter#735](https://github.com/kubernetes-sigs/karpenter/issues/735) - consolidateAfter TTL (244 reactions)

---

### 1.2 Migration from Cluster Autoscaler

#### [Issue #6544](https://github.com/aws/karpenter-provider-aws/issues/6544): "no service port 8443 found for service karpenter"
**Reactions:** 30 👍 | **Comments:** 37 | **Status:** Open
**Impact:** HIGH - Blocks migration
**Link:** https://github.com/aws/karpenter-provider-aws/issues/6544

**Problem:**
When migrating from Cluster Autoscaler following the official guide, NodePool creation fails with:
```
conversion webhook for karpenter.sh/v1beta1, Kind=NodePool failed:
Post "https://karpenter.kube-system.svc:8443/?timeout=30s":
no service port 8443 found for service "karpenter"
```

**Root Cause:**
- Karpenter installed in non-kube-system namespace
- Webhook configuration references wrong namespace
- Helm chart hardcoded namespace assumptions (fixed in later versions)

**Solutions:**
1. **Correct namespace configuration:**
   ```yaml
   webhook:
     enabled: true
     serviceNamespace: karpenter  # Match installation namespace
   ```

2. **Install both karpenter-crd and karpenter charts:**
   ```bash
   helm install karpenter-crd oci://public.ecr.aws/karpenter/karpenter-crd \
     --namespace karpenter --create-namespace \
     --set webhook.serviceNamespace=karpenter

   helm install karpenter oci://public.ecr.aws/karpenter/karpenter \
     --namespace karpenter
   ```

3. **Verify webhook service exists:**
   ```bash
   kubectl get svc -n karpenter karpenter
   kubectl get validatingwebhookconfigurations
   ```

**Related Issues:**
- [#6818](https://github.com/aws/karpenter-provider-aws/issues/6818) - Webhook namespace hardcoded (83 reactions)
- [#6847](https://github.com/aws/karpenter-provider-aws/issues/6847) - ArgoCD upgrade difficulties (63 reactions)
- [#6765](https://github.com/aws/karpenter-provider-aws/issues/6765) - Post-install hook ArgoCD sync issues (39 reactions)

---

### 1.3 v1.0 Migration Challenges

#### [Issue #6847](https://github.com/aws/karpenter-provider-aws/issues/6847): ArgoCD/FluxCD Upgrade Difficulties
**Reactions:** 63 👍 | **Comments:** 95 | **Status:** Closed
**Impact:** HIGH - GitOps workflows broken
**Link:** https://github.com/aws/karpenter-provider-aws/issues/6847

**Problem:**
- v1.0.0 chart embeds static CRDs that don't respect Helm values
- ArgoCD detects drift when CRDs are managed separately
- `webhook.serviceName` value not templated in embedded CRDs
- Duplicate resource errors with dual-chart approach

**Solutions:**
1. **Clear managed fields before upgrade:**
   ```bash
   kubectl proxy &
   curl -X PATCH -H 'Content-Type: application/merge-patch+json' \
     -d '{"metadata":{"managedFields": [{}]}}' \
     http://127.0.0.1:8001/apis/karpenter.sh/v1beta1/nodepools/<name>
   ```

2. **Use separate CRD chart approach:**
   ```yaml
   # Install CRDs first
   apiVersion: helm.toolkit.fluxcd.io/v2
   kind: HelmRelease
   metadata:
     name: karpenter-crd
   spec:
     chart:
       spec:
         chart: karpenter-crd
         version: 1.0.x
     values:
       webhook:
         enabled: true
         serviceNamespace: karpenter

   # Then main chart with CRDs skipped
   ---
   apiVersion: helm.toolkit.fluxcd.io/v2
   kind: HelmRelease
   metadata:
     name: karpenter
   spec:
     chart:
       spec:
         chart: karpenter
         version: 1.0.x
     install:
       crds: Skip
     upgrade:
       crds: Skip
   ```

3. **ArgoCD specific fix - disable CRD management:**
   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata:
     name: karpenter
   spec:
     syncPolicy:
       syncOptions:
         - CreateNamespace=true
         - ServerSideApply=true
   ```

#### [Issue #6818](https://github.com/aws/karpenter-provider-aws/issues/6818): Webhook Namespace Hardcoded
**Reactions:** 83 👍 | **Comments:** 23 | **Status:** Closed
**Impact:** HIGH
**Link:** https://github.com/aws/karpenter-provider-aws/issues/6818

**Problem:**
v1.0.0 conversion webhook hardcoded to `kube-system` namespace causing failures when installed elsewhere.

**Solution:**
Fixed in v1.0.1+ - ensure you're using latest patch version.

---

### 1.4 Node Lifecycle & NotReady Nodes

#### [Issue #7029](https://github.com/aws/karpenter-provider-aws/issues/7029): "Kubelet stopped posting node status"
**Reactions:** 51 👍 | **Comments:** 31 | **Status:** Open
**Impact:** CRITICAL - Nodes become unusable
**Link:** https://github.com/aws/karpenter-provider-aws/issues/7029

**Problem:**
- Nodes suddenly go NotReady with "Kubelet stopped posting node status"
- All node conditions show "Unknown"
- Pods stuck in Terminating state indefinitely
- Often related to Bottlerocket AMI version changes
- Can affect 6+ out of 12 nodes simultaneously
- Common error: `failed to read podLogsRootDirectory "/var/log/pods": open /var/log/pods: too many open files`

**Root Causes:**
1. File descriptor exhaustion (too many open files)
2. Bottlerocket AMI version mismatches
3. Node controller conflicts with Karpenter disruption logic

**Solutions:**
1. **Immediate recovery - reboot instance:**
   ```bash
   # Find instance ID
   kubectl get node <node-name> -o jsonpath='{.spec.providerID}'

   # Reboot via AWS CLI
   aws ec2 reboot-instances --instance-ids i-xxxxx
   ```

2. **Preventive measures:**
   - Pin Bottlerocket AMI version instead of using `@latest`
   - Monitor file descriptor usage
   - Set file limits in kubelet configuration
   - Configure node repair/replacement:
     ```yaml
     spec:
       disruption:
         consolidateAfter: 30s
       template:
         spec:
           expireAfter: 168h  # Force refresh weekly
     ```

**Related Issues:**
- [kubernetes-sigs/karpenter#750](https://github.com/kubernetes-sigs/karpenter/issues/750) - Node repair automation (152 reactions, closed)
- [kubernetes-sigs/karpenter#1573](https://github.com/kubernetes-sigs/karpenter/issues/1573) - Node NotReady and terminating (12 reactions)

#### [Issue #6905](https://github.com/aws/karpenter-provider-aws/issues/6905): NodeClaims Stranded After NodePool Deletion
**Reactions:** 28 👍 | **Comments:** 22 | **Status:** Open
**Link:** https://github.com/aws/karpenter-provider-aws/issues/6905

**Problem:**
- Deleting NodePool leaves NodeClaims with deletion timestamp but stuck
- Error: "Cannot disrupt NodeClaim: state node is marked for deletion"
- NodeClaims have finalizer but never complete deletion

**Solutions:**
1. **Force finalizer removal (use with caution):**
   ```bash
   kubectl patch nodeclaim <name> -p '{"metadata":{"finalizers":[]}}' --type=merge
   ```

2. **Ensure clean shutdown:**
   - Scale workloads to zero before deleting NodePool
   - Wait for nodes to be empty
   - Use `kubectl delete nodepool <name> --wait=true`

---

### 1.5 Subnet & Network Resource Exhaustion

#### [Issue #2921](https://github.com/aws/karpenter-provider-aws/issues/2921) + [#5234](https://github.com/aws/karpenter-provider-aws/issues/5234): Subnet IP Exhaustion
**Combined Reactions:** 175+ 👍 | **Status:** Feature request (assigned)
**Links:**
- https://github.com/aws/karpenter-provider-aws/issues/2921
- https://github.com/aws/karpenter-provider-aws/issues/5234

**Problem:**
- Karpenter selects subnets randomly without checking available IPs
- Nodes fail to join cluster when subnet runs out of IPs
- "InsufficientFreeAddressesInSubnet" errors
- VPC CNI fails to assign IPs, nodes become NotReady

**Impact:**
Critical for large clusters or clusters with small CIDR blocks.

**Solutions:**
1. **Monitor subnet capacity:**
   ```bash
   aws ec2 describe-subnets \
     --subnet-ids subnet-xxx \
     --query 'Subnets[0].AvailableIpAddressCount'
   ```

2. **Use subnet tags to exclude exhausted subnets:**
   ```yaml
   spec:
     subnetSelectorTerms:
       - tags:
           karpenter.sh/discovery: my-cluster
           kubernetes.io/role/internal-elb: "1"
       - tags:
           Name: subnet-with-capacity  # Explicitly name good subnets
   ```

3. **Expand VPC CIDR or migrate to IPv6:**
   - Add secondary CIDR blocks to VPC
   - Enable IPv6 (eliminates IP exhaustion)
   - Use IP prefix delegation mode for VPC CNI

4. **Temporary workaround - limit zones:**
   ```yaml
   requirements:
     - key: topology.kubernetes.io/zone
       operator: In
       values:
         - us-east-1a  # Only zones with IP availability
         - us-east-1c
   ```

**Feature Status:** Planned feature to auto-detect subnet capacity

---

### 1.6 Spot Instance & Interruption Handling

#### [Issue #2813](https://github.com/aws/karpenter-provider-aws/issues/2813): Handle Rebalance Recommendation Events
**Reactions:** 69 👍 | **Comments:** 18 | **Status:** Open (assigned)
**Link:** https://github.com/aws/karpenter-provider-aws/issues/2813

**Problem:**
- 2-minute spot interruption warning insufficient for slow-draining workloads
- NLB IP target mode deregistration takes too long
- Spot rebalance recommendations not handled by default

**Current Workarounds:**
1. Use Node Termination Handler (NTH) alongside Karpenter
2. Increase pod `terminationGracePeriodSeconds`
3. Use readiness gates with deregistration delays

**Best Practice:**
```yaml
# Pod spec
spec:
  terminationGracePeriodSeconds: 300
  containers:
    - lifecycle:
        preStop:
          exec:
            command:
              - /bin/sh
              - -c
              - sleep 30  # Allow NLB to drain
```

#### [Issue #4673](https://github.com/aws/karpenter-provider-aws/issues/4673): ELB Connection Draining Support
**Reactions:** 19 👍 | **Comments:** 29 | **Status:** Open
**Link:** https://github.com/aws/karpenter-provider-aws/issues/4673

**Solution:**
Use `karpenter.sh/do-not-disrupt` during critical periods and implement connection draining at application level.

---

### 1.7 Disruption Control Issues

#### [Issue #6803](https://github.com/aws/karpenter-provider-aws/issues/6803): "Cannot disrupt: state node isn't initialized"
**Reactions:** 19 👍 | **Comments:** 10 | **Status:** Under investigation
**Link:** https://github.com/aws/karpenter-provider-aws/issues/6803

**Problem:**
- NodeClaims stuck in unready state
- Missing `karpenter.sh/initialized` label
- Disruption blocked indefinitely
- Error: "Cannot disrupt NodeClaim: state node isn't initialized"

**Root Cause:**
Race condition during node registration/initialization phase.

**Solutions:**
1. **Delete and recreate stuck NodeClaim:**
   ```bash
   kubectl delete nodeclaim <name>
   # Let Karpenter recreate
   ```

2. **Check node initialization issues:**
   ```bash
   kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter
   # Look for registration errors

   # Check node for issues
   kubectl describe node <node-name>
   ```

---

## 2. Top Feature Requests (by Community Demand)

### 2.1 Warm Pools / Node Hibernation
**Issues:** [#3798](https://github.com/aws/karpenter-provider-aws/issues/3798), [#4354](https://github.com/aws/karpenter-provider-aws/issues/4354)
**Total Reactions:** 307 👍
**Status:** Open (high priority)
**Links:**
- https://github.com/aws/karpenter-provider-aws/issues/3798
- https://github.com/aws/karpenter-provider-aws/issues/4354

**Request:**
Pre-provision stopped (hibernated) instances that can start quickly when needed, similar to ASG warm pools.

**Use Case:**
- Rapid scaling for unpredictable workloads
- Reduce 2-3 minute node provisioning time to seconds
- Cost-effective compared to always-running headroom

**Current Workaround:**
Deploy low-priority pause pods that get evicted when real workloads need capacity.

---

### 2.2 Dynamic Storage Scaling
**Issue:** [#2394](https://github.com/aws/karpenter-provider-aws/issues/2394)
**Total Reactions:** 180 👍
**Status:** Open (accepted, v1.x)
**Link:** https://github.com/aws/karpenter-provider-aws/issues/2394

**Request:**
Dynamically scale EBS volume size based on pod ephemeral-storage requests.

**Current Limitation:**
Block device mappings in EC2NodeClass are static for all instances.

**Workaround:**
Create multiple NodePools/EC2NodeClasses with different storage configurations and use node selectors.

---

### 2.3 Fleet Allocation Strategy Control
**Issue:** [#1240](https://github.com/aws/karpenter-provider-aws/issues/1240)
**Total Reactions:** 162 👍
**Status:** Open (accepted, cost-optimization label)
**Link:** https://github.com/aws/karpenter-provider-aws/issues/1240

**Request:**
Control EC2 Fleet allocation strategy (currently hardcoded to `capacity-optimized-prioritized` for spot, `lowest-price` for on-demand).

**Use Cases:**
- Cost-sensitive workloads preferring `lowest-price` strategy
- Capacity-sensitive workloads needing `capacity-optimized`
- Fine-tuning spot diversification

---

### 2.4 Savings Plans & Reserved Instance Support
**Issue:** [#2259](https://github.com/aws/karpenter-provider-aws/issues/2259)
**Total Reactions:** 46 👍
**Status:** Open (important-longterm)
**Link:** https://github.com/aws/karpenter-provider-aws/issues/2259

**Request:**
Karpenter should be aware of Savings Plans and use on-demand capacity up to commitment, then use spot.

**Current Gap:**
No way to specify "use X amount of on-demand, then spot" - Karpenter treats both equally based on cost.

---

## 3. Karpenter Deployment Strategies & Limitations

### 3.1 Where to Run Karpenter Controller

Karpenter controller itself needs compute capacity to run. This creates a critical architectural decision with significant operational implications.

#### Deployment Option Comparison

| Factor | Managed Node Group | Fargate | Self-Managed EC2 |
|--------|-------------------|---------|------------------|
| **Operational Overhead** | Low | Lowest | High |
| **Cost** | Medium | Higher (~30% more) | Lowest |
| **Startup Time** | 2-3 minutes | Instant | 3-5 minutes |
| **Probe Timeout Issues** | No | Yes ([#8580](https://github.com/aws/karpenter-provider-aws/issues/8580)) | No |
| **Pod Identity Support** | Yes | **No** | Yes |
| **Logging Flexibility** | Full | Limited ([#7718](https://github.com/aws/karpenter-provider-aws/issues/7718)) | Full |
| **Karpenter Can Manage** | No (circular dependency) | No | No |
| **Production Ready** | **Yes (Recommended)** | Yes with caveats | Yes |
| **HA Considerations** | Auto-healing via ASG | AWS managed | Manual |
| **Best Use Case** | Production clusters | Serverless/minimal ops | Advanced users |

---

### 3.2 Managed Node Group Deployment (Recommended)

**[Issue #6601](https://github.com/aws/karpenter-provider-aws/issues/6601): Request to manage non-Karpenter nodes** (4 reactions)

#### Why Recommended:
- ✅ **No circular dependency** - Karpenter can't manage itself
- ✅ **Proven stability** - Most production deployments use this
- ✅ **Full feature support** - No limitations on probes, logging, or IAM
- ✅ **Lower cost** than Fargate for always-running workloads
- ✅ **Auto-healing** via ASG health checks

#### Configuration:

```yaml
# eksctl cluster config
managedNodeGroups:
  - name: karpenter-system
    instanceType: t3.medium
    desiredCapacity: 2  # HA for karpenter controller
    minSize: 2
    maxSize: 3
    labels:
      karpenter.sh/controller: "true"
    taints:
      - key: CriticalAddonsOnly
        value: "true"
        effect: NoSchedule
```

**Karpenter Helm values:**
```yaml
# Pin karpenter to system node group
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: karpenter.sh/controller
              operator: In
              values: ["true"]

tolerations:
  - key: CriticalAddonsOnly
    operator: Exists
    effect: NoSchedule

# Run 2 replicas for HA
replicas: 2
```

#### Operational Considerations:

**Node Lifecycle Management:**
The managed node group requires manual AMI updates and instance refreshes. Consider:
1. **Automated AMI updates:** Use Lambda/EventBridge to detect new EKS-optimized AMIs
2. **Scheduled instance refreshes:** Weekly or monthly based on risk tolerance
3. **Separate from Karpenter-managed nodes:** Use different security groups/subnets if needed

**Cost Impact:**
- Small managed node group (2x t3.medium): ~$60-80/month
- Always-on cost for system workloads
- Consider using spot for non-critical clusters

---

### 3.3 Fargate Deployment

**[Issue #8580](https://github.com/aws/karpenter-provider-aws/issues/8580): Readiness/Liveness probe failures on Fargate**
**[Issue #7718](https://github.com/aws/karpenter-provider-aws/issues/7718): Log output configuration doesn't work on Fargate** (10 comments)
**[Issue #8373](https://github.com/aws/karpenter-provider-aws/issues/8373): Fargate IAM setup complications** (7 comments)

#### Advantages:
- ✅ No node management overhead
- ✅ No need for initial managed node group
- ✅ Instant scaling (no node startup time)
- ✅ AWS manages patching and availability

#### Limitations & Issues:

**1. Health Probe Timeouts**
```
Warning  Unhealthy  context deadline exceeded (Client.Timeout exceeded while awaiting headers)
```
**Cause:** Fargate networking initialization delay
**Solution:**
```yaml
# Increase probe timeouts
livenessProbe:
  initialDelaySeconds: 60  # Increased from 30
  periodSeconds: 15  # Increased from 10
  timeoutSeconds: 5   # Increased from 1
  failureThreshold: 5  # Increased from 3

readinessProbe:
  initialDelaySeconds: 30  # Increased from 0
  periodSeconds: 15  # Increased from 10
  timeoutSeconds: 5
```

**2. Pod Identity NOT Supported**
Fargate does NOT support EKS Pod Identity (as of Dec 2025). Must use IRSA.

```yaml
# Terraform module configuration for Fargate
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  enable_irsa = true
  create_pod_identity_association = false  # CRITICAL for Fargate
}
```

**3. Logging Limitations**
Cannot write logs to filesystem for sidecar log collectors (like Promtail for Loki).

**Workarounds:**
- Use AWS Fargate Fluent Bit (limited destinations)
- Stream to CloudWatch Logs
- Accept stdout-only logging

**4. DNS Configuration Required**
```yaml
# Karpenter Helm values for Fargate
dnsPolicy: Default  # REQUIRED - cluster DNS not available during startup

tolerations:
  - key: "eks.amazonaws.com/compute-type"
    operator: "Equal"
    value: "fargate"
    effect: "NoSchedule"

nodeSelector:
  eks.amazonaws.com/compute-type: fargate
```

**5. Resource Sizing**
Fargate rounds up to specific CPU/memory combinations. Monitor actual usage vs allocated.

#### When to Use Fargate:

✅ **Good For:**
- Development/testing clusters
- Serverless-first organizations
- Minimal operational overhead priority
- Cost is secondary to simplicity
- No logging/monitoring sidecar requirements

❌ **Avoid For:**
- Cost-sensitive production workloads
- Need for Pod Identity
- Complex logging requirements (Loki, custom collectors)
- Tight probe timeout requirements

**Example Fargate Configuration:**

```yaml
# Fargate profile for karpenter namespace
fargate_profiles = {
  karpenter = {
    selectors = [
      { namespace = "karpenter" }
    ]
  }
}

# Karpenter Helm values
values = [
  <<-EOT
  dnsPolicy: Default
  settings:
    clusterName: ${cluster_name}
    clusterEndpoint: ${cluster_endpoint}
    interruptionQueue: ${queue_name}

  serviceAccount:
    annotations:
      eks.amazonaws.com/role-arn: ${iam_role_arn}

  # Fargate-specific configuration
  tolerations:
    - key: "eks.amazonaws.com/compute-type"
      operator: "Equal"
      value: "fargate"
      effect: "NoSchedule"

  nodeSelector:
    eks.amazonaws.com/compute-type: fargate

  # Increased timeouts for Fargate
  controller:
    healthProbe:
      port: 8081
    resources:
      requests:
        cpu: 1
        memory: 1Gi
      limits:
        cpu: 1
        memory: 1Gi

  webhook:
    enabled: true
    port: 8443
  EOT
]
```

**Fargate-Specific Issues to Watch:**
- [#8580](https://github.com/aws/karpenter-provider-aws/issues/8580) - Probe failures (recent issue)
- [#7718](https://github.com/aws/karpenter-provider-aws/issues/7718) - Logging configuration
- [#5352](https://github.com/aws/karpenter-provider-aws/issues/5352) - Log output paths on Fargate
- [#6898](https://github.com/aws/karpenter-provider-aws/issues/6898) - TLS handshake errors (51 reactions)

---

### 3.4 The Circular Dependency Problem

**Core Issue:** Karpenter cannot manage the nodes it runs on.

**Why?**
If Karpenter disrupts/terminates the node running its own controller, the controller stops, and no new nodes can be provisioned until the controller restarts elsewhere.

**Solutions:**

**1. Dedicated System Node Pool** (Recommended for mixed approach)
```yaml
# Separate NodePool for system workloads (including karpenter)
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: system
spec:
  weight: 100  # Highest priority

  disruption:
    consolidationPolicy: WhenEmpty  # Very conservative
    consolidateAfter: 1h
    budgets:
      - nodes: "0"  # Never disrupt system nodes

  template:
    metadata:
      labels:
        node-role: system

    spec:
      expireAfter: 720h  # Long TTL
      terminationGracePeriod: 24h  # Give plenty of time

      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]  # Never spot for system

        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["t3.medium", "t3.large"]  # Small, cost-effective

      taints:
        - key: CriticalAddonsOnly
          effect: NoSchedule
```

**2. Node Affinity for Karpenter**
```yaml
# Ensure Karpenter NEVER runs on nodes it manages
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            # Prefer managed node group
            - key: eks.amazonaws.com/nodegroup
              operator: Exists
            # OR prefer fargate
            # - key: eks.amazonaws.com/compute-type
            #   operator: In
            #   values: ["fargate"]
            # OR prefer system NodePool
            # - key: node-role
            #   operator: In
            #   values: ["system"]
```

**3. Mixed Strategy** (Best Practice for Large Clusters)
- **Small managed node group** (2-3 nodes) for:
  - Karpenter controller
  - CoreDNS
  - Critical monitoring (Prometheus, etc.)
  - CNI/CSI drivers

- **Karpenter-managed nodes** for:
  - All application workloads
  - Batch jobs
  - Stateful services (with appropriate settings)

---

### 3.5 Deployment Strategy Decision Tree

```
Do you need absolute minimal operational overhead?
├─ Yes → Fargate (accept higher cost + limitations)
└─ No → Continue

Is cost optimization critical (>100 nodes)?
├─ Yes → Managed Node Group + Karpenter
└─ No → Continue

Do you need Pod Identity?
├─ Yes → Managed Node Group (Fargate doesn't support it)
└─ No → Continue

Do you need custom logging (Loki, etc.)?
├─ Yes → Managed Node Group
└─ No → Fargate acceptable

Is this a production cluster?
├─ Yes → Managed Node Group (proven stability)
└─ No → Fargate acceptable for dev/test
```

---

### 3.6 Hybrid Deployment Pattern (Advanced)

Run Karpenter on Fargate for dev clusters, managed node groups for production:

```yaml
# Development clusters
fargate_profiles = {
  karpenter = { selectors = [{ namespace = "karpenter" }] }
  kube-system = { selectors = [{ namespace = "kube-system" }] }
}

# Production clusters
managed_node_groups = {
  karpenter-system = {
    desired_size = 2
    min_size = 2
    max_size = 3
    instance_types = ["t3.medium"]

    labels = {
      role = "karpenter-controller"
    }

    taints = [{
      key    = "CriticalAddonsOnly"
      value  = "true"
      effect = "NO_SCHEDULE"
    }]
  }
}
```

**Cost Comparison (Approximate):**
- **Managed Node Group (2x t3.medium):** $60-80/month
- **Fargate (2x 0.25 vCPU/512MB):** $85-100/month
- **Trade-off:** $20-40/month vs operational simplicity

---

### 3.7 Authentication Methods: IRSA vs Pod Identity

**Modern Approach (Kubernetes 1.24+):**

| Method | Fargate Support | Managed Node Group | Complexity | Recommended |
|--------|-----------------|-------------------|------------|-------------|
| **IRSA** (IAM Roles for Service Accounts) | ✅ Yes | ✅ Yes | Medium | Fargate only |
| **Pod Identity** (EKS Pod Identity) | ❌ No | ✅ Yes | Low | **Managed nodes** |

**[Issue #8206](https://github.com/aws/karpenter-provider-aws/issues/8206): Confusion about IRSA vs Pod Identity** (6 comments)
**[Issue #5369](https://github.com/aws/karpenter-provider-aws/issues/5369): Update docs for EKS Access Entry API** (41 reactions)

#### Pod Identity Configuration (Managed Nodes Only):

```yaml
# Terraform module
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = module.eks.cluster_name

  # Use modern Pod Identity
  enable_pod_identity = true
  create_pod_identity_association = true

  # Disable IRSA
  enable_irsa = false
}
```

#### IRSA Configuration (Required for Fargate):

```yaml
module "karpenter" {
  source = "terraform-aws-modules/eks/aws//modules/karpenter"

  cluster_name = module.eks.cluster_name

  # Use IRSA for Fargate
  enable_irsa = true
  irsa_oidc_provider_arn = module.eks.oidc_provider_arn

  # Fargate doesn't support Pod Identity
  create_pod_identity_association = false
}
```

**Helm values:**
```yaml
serviceAccount:
  annotations:
    eks.amazonaws.com/role-arn: ${karpenter_iam_role_arn}  # For IRSA
```

---

### 3.8 Critical: Node Affinity Configuration

**Without proper node affinity, Karpenter will try to manage its own nodes!**

#### Anti-Pattern: Karpenter Managing Itself
```yaml
# ❌ DANGEROUS - Karpenter can disrupt itself
# No affinity configured - Karpenter pods can run anywhere
```

**Result:**
- Karpenter disrupts node running its controller
- Controller stops
- Cluster can't scale
- Manual intervention required

#### Solution: Exclude Karpenter-managed Nodes

```yaml
# ✅ GOOD - For Managed Node Group
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: karpenter.sh/nodepool
              operator: DoesNotExist  # NOT on Karpenter nodes
            - key: eks.amazonaws.com/nodegroup
              operator: Exists  # Only managed node groups

# ✅ GOOD - For Fargate
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
        - matchExpressions:
            - key: eks.amazonaws.com/compute-type
              operator: In
              values: ["fargate"]

tolerations:
  - key: eks.amazonaws.com/compute-type
    operator: Equal
    value: fargate
    effect: NoSchedule
```

---

### 3.9 Common Deployment Mistakes

#### Mistake #1: No HA Configuration
```yaml
# ❌ BAD - Single point of failure
replicas: 1

# ✅ GOOD - High availability
replicas: 2

topologySpreadConstraints:
  - maxSkew: 1
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule
```

#### Mistake #2: Insufficient Resources
```yaml
# ❌ BAD - Controller will OOM in large clusters
resources:
  requests:
    memory: 512Mi
    cpu: 500m

# ✅ GOOD - Adequate for medium clusters (<500 nodes)
resources:
  requests:
    memory: 1Gi
    cpu: 1
  limits:
    memory: 1Gi
    cpu: 1

# ✅ BETTER - For large clusters (>500 nodes)
resources:
  requests:
    memory: 2Gi
    cpu: 2
  limits:
    memory: 2Gi
    cpu: 2
```

#### Mistake #3: Wrong dnsPolicy
```yaml
# ❌ FAILS on Fargate - cluster DNS not available at startup
# dnsPolicy: ClusterFirst (default)

# ✅ REQUIRED for Fargate
dnsPolicy: Default
```

#### Mistake #4: Fargate with Pod Identity
```yaml
# ❌ WILL NOT WORK - Fargate doesn't support Pod Identity
create_pod_identity_association = true

# ✅ Must use IRSA for Fargate
enable_irsa = true
```

---

### 3.10 Monitoring Karpenter Controller Health

**Critical Metrics:**

```promql
# Controller pod availability
up{job="karpenter"} == 0

# Controller restarts
rate(kube_pod_container_status_restarts_total{namespace="karpenter"}[5m]) > 0

# Memory pressure
container_memory_usage_bytes{namespace="karpenter"}
  / container_spec_memory_limit_bytes{namespace="karpenter"} > 0.9

# Controller not reconciling
rate(controller_runtime_reconcile_total{controller="provisioner"}[5m]) == 0
```

---

### 3.11 Deployment Architecture Examples

#### Small Cluster (<50 nodes)
```
┌─────────────────────────────────────────────┐
│  Managed Node Group (t3.medium x2)         │
│  ├─ Karpenter Controller (2 replicas)      │
│  ├─ CoreDNS                                 │
│  └─ System DaemonSets                       │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Karpenter-Managed Nodes (dynamic)          │
│  ├─ Application Pods                        │
│  └─ Scales 0 to N based on demand          │
└─────────────────────────────────────────────┘
```

#### Large Cluster (>100 nodes)
```
┌─────────────────────────────────────────────┐
│  Managed Node Group (m5.large x3)           │
│  ├─ Karpenter Controller (2 replicas)       │
│  ├─ Prometheus/Grafana                      │
│  ├─ Critical monitoring                     │
│  └─ Load balancer controllers               │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Karpenter NodePool: general-workloads      │
│  ├─ Application Pods (most traffic)         │
│  └─ Scales 10-200 nodes                     │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Karpenter NodePool: batch-jobs             │
│  ├─ Short-lived batch workloads             │
│  └─ Scales 0-100 nodes, aggressive cleanup  │
└─────────────────────────────────────────────┘

┌─────────────────────────────────────────────┐
│  Karpenter NodePool: stateful               │
│  ├─ Databases, caches                       │
│  └─ Conservative disruption, on-demand only │
└─────────────────────────────────────────────┘
```

---

## 4. Most Common Configuration Mistakes

### 4.1 IAM Permission Issues

**Common Errors:**
```
Controller isn't authorized to call ec2:RunInstances
api error AccessDenied: explicit deny in a service control policy
```

**Required Permissions Checklist:**
- ✅ EC2: `RunInstances`, `TerminateInstances`, `DescribeInstances`, `DescribeInstanceTypes`, `DescribeImages`, `DescribeLaunchTemplates`, `CreateFleet`, `DescribeSubnets`, `DescribeSecurityGroups`, `DescribeSpotPriceHistory`
- ✅ IAM: `PassRole` for node instance profile
- ✅ EKS: `DescribeCluster`
- ✅ SQS: `DeleteMessage`, `GetQueueAttributes`, `ReceiveMessage` (for interruption queue)
- ✅ Pricing: `GetProducts`
- ✅ SSM: `GetParameter`

**[Issue #8190](https://github.com/aws/karpenter-provider-aws/issues/8190): SCP Policy Conflicts**
**Impact:** Blocks v0.30 → v1.x upgrades
**Link:** https://github.com/aws/karpenter-provider-aws/issues/8190

**Problem:**
v1.x changed how `ec2:RunInstances` is called - no longer via `ec2fleet.amazonaws.com` service, causing SCP denials.

**Solution:**
Update SCPs to allow Karpenter controller role, or use VPC endpoints with conditions.

---

### 4.2 Webhook Configuration (v1.0+ Migrations)

**Common Issues:**
1. Webhook service name mismatch
2. Namespace hardcoding (kube-system vs actual namespace)
3. TLS handshake errors ([#6898](https://github.com/aws/karpenter-provider-aws/issues/6898): 51 reactions)
4. Conversion webhook failures with GitOps

**Best Practice Configuration:**
```yaml
# karpenter-crd chart
webhook:
  enabled: true
  serviceName: karpenter
  serviceNamespace: karpenter  # CRITICAL: Match installation namespace
  port: 8443

# karpenter main chart
webhook:
  enabled: true
  port: 8443
```

**TLS Handshake Errors:**
```
ERROR: http: TLS handshake error from xx: read tcp: connection reset by peer
```

**Solutions:**
- Restart karpenter pods to refresh certificates
- Check certificate rotation
- Verify webhook service endpoints
- Known issue with Kubernetes cert caching (resolved in most cases by waiting)

---

### 4.3 NodePool & EC2NodeClass Design Anti-Patterns

**Issue #1:** Too aggressive `consolidateAfter`
```yaml
# ❌ BAD - Causes thrashing
spec:
  disruption:
    consolidateAfter: 1s  # Way too aggressive!

# ✅ GOOD - Allows workload stabilization
spec:
  disruption:
    consolidateAfter: 5m  # Or higher for batch workloads
```

**Issue #2:** Missing disruption budgets
```yaml
# ❌ BAD - Can disrupt entire pool at once
spec:
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized

# ✅ GOOD - Limits blast radius
spec:
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 5m
    budgets:
      - nodes: "10%"  # Only disrupt 10% at a time
```

**Issue #3:** No `expireAfter` configuration
```yaml
# ✅ GOOD - Regular node refresh for security
spec:
  template:
    spec:
      expireAfter: 720h  # 30 days
      terminationGracePeriod: 2h  # v1.0+ feature
```

---

## 5. Common Error Messages & Solutions

### 5.1 "Cannot disrupt NodeClaim: state node is nominated for a pending pod"

**Issue:** [#7521](https://github.com/aws/karpenter-provider-aws/issues/7521) (25 reactions)
**Link:** https://github.com/aws/karpenter-provider-aws/issues/7521

**Cause:**
Karpenter nominated pod to node, but pod hasn't scheduled yet. Disruption blocked during this window.

**Solutions:**
1. Check for genuinely pending pods:
   ```bash
   kubectl get pods --all-namespaces --field-selector=status.phase=Pending
   ```

2. If no pending pods exist, likely stale nomination - restart karpenter controller:
   ```bash
   kubectl rollout restart deployment karpenter -n karpenter
   ```

3. Check for scheduling constraints blocking pod:
   ```bash
   kubectl describe pod <pod-name> | grep -A 5 Events
   ```

---

### 5.2 "all available instance types exceed limits"

**Issue:** [#5937](https://github.com/aws/karpenter-provider-aws/issues/5937) (32 reactions)
**Link:** https://github.com/aws/karpenter-provider-aws/issues/5937

**Causes:**
1. NodePool limits too restrictive
2. Instance type requirements too narrow
3. Temporary AWS capacity issues

**Debugging:**
```bash
# Check NodePool limits
kubectl get nodepool <name> -o yaml | grep -A 10 limits

# Check what's being requested
kubectl describe pod <pending-pod> | grep -A 10 "Requests:"

# View Karpenter's reasoning
kubectl logs -n karpenter -l app.kubernetes.io/name=karpenter | grep "excluded"
```

**Solutions:**
1. Expand instance type selection
2. Increase resource limits
3. Check for zone-specific capacity constraints

---

### 5.3 "Failed to detect the cluster CIDR"

**Issue:** [#7875](https://github.com/aws/karpenter-provider-aws/issues/7875) (43 reactions)
**Link:** https://github.com/aws/karpenter-provider-aws/issues/7875

**Cause:**
IAM permissions issue - cannot call `eks:DescribeCluster`.

**Solutions:**
1. **Verify IAM policy includes:**
   ```json
   {
     "Effect": "Allow",
     "Action": "eks:DescribeCluster",
     "Resource": "arn:aws:eks:region:account:cluster/cluster-name"
   }
   ```

2. **Force EC2NodeClass reconciliation:**
   ```bash
   kubectl annotate ec2nodeclass <name> karpenter.sh/refresh="$(date +%s)"
   ```

3. **EC2NodeClass will be stuck NotReady** until IAM is fixed - no auto-retry on this specific error (known issue).

---

### 5.4 "Pod has a preferred Anti-Affinity which can prevent consolidation"

**Impact:** Informational warning, not an error

**Meaning:**
Karpenter detected pod with `preferredDuringSchedulingIgnoredDuringExecution` anti-affinity. This may make consolidation harder but won't block it entirely.

**Action:**
Review if `requiredDuringSchedulingIgnoredDuringExecution` is more appropriate for your use case.

---

## 6. Version-Specific Issues & Migration Guides

### 6.1 v0.27 → v0.32 (2023)

**Key Changes:**
- Consolidation feature introduced (v0.27)
- Machine → NodeClaim terminology (v0.28)
- Drift detection added (v0.29)

**Common Issues:**
- Initial consolidation was too aggressive
- Node churn from immature algorithms
- `ttlSecondsAfterEmpty` and `ttlSecondsUntilExpired` confusion

---

### 6.2 v0.32 → v0.37 (2023-2024)

**Key Changes:**
- v1beta1 API introduced (v0.32)
- Disruption budgets added
- `consolidateAfter` parameter introduced
- Improved consolidation algorithms

**Common Issues:**
- High node churn after v0.36 upgrade ([#7344](https://github.com/aws/karpenter-provider-aws/issues/7344): 13 reactions)
- Consolidation rate increased unexpectedly
- ECR image pull costs spiked from frequent node replacements

**Solutions:**
- Tune `consolidateAfter` to 5m-15m based on workload
- Implement image caching strategies
- Use disruption budgets

---

### 6.3 v0.37 → v1.0 (2024) - MAJOR BREAKING CHANGES

**Release Date:** August 2024
**Impact:** HIGH - Breaking API changes

**Major Changes:**
1. **API Version:** v1beta1 → v1
2. **CRDs:** Separate `karpenter-crd` chart introduced
3. **Webhook:** Conversion webhook required for v1beta1 compatibility
4. **Disruption:** `expireAfter` no longer respects disruption budgets (breaking change)
5. **Helm:** CRDs embedded in main chart (ArgoCD/Flux issues)

**Migration Checklist:**

- [ ] Update to v0.37.x first (latest v0 release)
- [ ] Review v1 migration guide: https://karpenter.sh/docs/upgrading/upgrade-guide/
- [ ] Update IAM policies (no changes, but verify)
- [ ] Install `karpenter-crd` chart separately (for GitOps)
- [ ] Update NodePool manifests from v1beta1 to v1
- [ ] Update EC2NodeClass (formerly AWSNodeTemplate)
- [ ] Test in non-production first
- [ ] Understand new termination behavior:
  ```yaml
  # v1.0 introduces terminationGracePeriod
  spec:
    disruption:
      consolidateAfter: 30s
    template:
      spec:
        expireAfter: 720h
        terminationGracePeriod: 48h  # New in v1.0
  ```

**Breaking Behavior Changes:**

1. **Expiration is now forceful:**
   - v0.37: `expireAfter` respected PDBs and `do-not-disrupt`
   - v1.0: `expireAfter` is forceful unless `terminationGracePeriod` is set
   - Set `terminationGracePeriod: null` for v0.37-like behavior

2. **Conversion webhook required:**
   - v1beta1 resources auto-convert to v1
   - Requires webhook service running in correct namespace

---

### 6.4 v1.0 → v1.8 (2024-2025)

**Evolution:**
- v1.0: Initial stable release
- v1.1-1.3: Bug fixes and stabilization
- v1.4+: Performance improvements
- v1.8: Latest (current as of Dec 2025)

**Notable Fixes:**
- Hash collision prevention for subnet/SG resolution ([#8664](https://github.com/aws/karpenter-provider-aws/issues/8664))
- Improved disruption timing
- Better handling of drift scenarios
- StaticCapacity feature gate issues ([#8608](https://github.com/aws/karpenter-provider-aws/issues/8608))

---

## 7. Best Practices & Recommendations

### 7.1 Production-Ready NodePool Configuration

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: production-workloads
spec:
  # Disruption controls
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 15m  # Wait 15min before consolidating
    budgets:
      # Only disrupt 10% during business hours
      - nodes: "10%"
        schedule: "0 9-17 * * MON-FRI"
        duration: 8h
      # More aggressive during off-hours
      - nodes: "30%"
        schedule: "0 18-8 * * *"

  # Resource limits
  limits:
    cpu: 1000
    memory: 1000Gi

  template:
    metadata:
      labels:
        environment: production
        managed-by: karpenter

    spec:
      # Security & lifecycle
      expireAfter: 720h  # 30 days - force AMI refresh
      terminationGracePeriod: 2h  # Allow graceful shutdown

      # Node configuration
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default

      # Instance requirements
      requirements:
        # Capacity type - prefer spot but allow on-demand
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]

        # Modern instance types only
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["4"]

        # Limit to reasonable sizes
        - key: karpenter.k8s.aws/instance-size
          operator: NotIn
          values: ["nano", "micro", "small", "medium", "metal", "16xlarge", "24xlarge"]

        # Instance families
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["c5", "c6", "c7", "m5", "m6", "m7", "r5", "r6", "r7"]

        # Architecture
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]

        # Multi-AZ
        - key: topology.kubernetes.io/zone
          operator: In
          values: ["us-east-1a", "us-east-1b", "us-east-1c"]
```

### 7.2 EC2NodeClass Best Practices

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  # AMI Selection - PIN VERSION for stability
  amiFamily: AL2023
  amiSelectorTerms:
    - alias: al2023@v20241121  # Pinned, not @latest
    # Alternative: use specific AMI ID
    # - id: ami-xxxxx

  # Network configuration
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${CLUSTER_NAME}
        kubernetes.io/role/internal-elb: "1"

  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: ${CLUSTER_NAME}

  # IAM
  role: KarpenterNodeRole-${CLUSTER_NAME}

  # Storage
  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: 100Gi
        volumeType: gp3
        encrypted: true
        deleteOnTermination: true
        iops: 3000
        throughput: 125

  # Instance metadata
  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 1
    httpTokens: required  # IMDSv2

  # Tagging
  tags:
    Environment: production
    ManagedBy: karpenter
    NodePool: production-workloads
```

---

### 7.3 Monitoring & Alerting

**Critical Metrics to Monitor:**

```promql
# Nodes stuck in NotReady
count(kube_node_status_condition{condition="Ready",status="false"}
  * on (node) group_left() kube_node_labels{label_karpenter_sh_nodepool!=""})

# NodeClaims pending too long
count(karpenter_nodeclaims_created - karpenter_nodeclaims_registered > 900)

# Disruption blocked
rate(karpenter_disruption_blocked_total[5m]) > 0

# Consolidation actions
rate(karpenter_disruption_actions_performed_total{method="consolidation"}[1h])

# Resource limits approaching
karpenter_nodepool_usage{resource_type="cpu"} / karpenter_nodepool_limit{resource_type="cpu"} > 0.85
```

**Recommended Alerts:**

1. **Node stuck NotReady > 5 minutes**
2. **NodeClaim not registered within 15 minutes**
3. **Disruption blocked for > 1 hour on same node**
4. **NodePool at >90% limit**
5. **Consolidation rate > X nodes/hour** (threshold based on cluster size)

---

### 7.4 Cost Optimization Strategies

**From Community Experience:**

1. **Spot-First Strategy:**
   ```yaml
   requirements:
     - key: karpenter.sh/capacity-type
       operator: In
       values: ["spot", "on-demand"]
   # Karpenter prefers spot due to lower cost
   ```

2. **Instance Diversification for Spot:**
   ```yaml
   # Allow many instance families/sizes for better spot availability
   - key: karpenter.k8s.aws/instance-family
     operator: In
     values: ["c5", "c5a", "c5n", "c6a", "c6i", "m5", "m5a", "m6a", "m6i"]
   ```

3. **Consolidation Timing:**
   - Development clusters: aggressive (1-5m)
   - Staging: moderate (10-15m)
   - Production: conservative (30m-1h)

4. **Prevent Spot → On-Demand Cost Spike:**
   - Enable spot-to-spot consolidation feature flag
   - Monitor consolidation type in metrics
   - Use `do-not-disrupt` for cost-sensitive pods

---

## 8. Troubleshooting Playbook

### 8.1 Node Won't Join Cluster

**Symptoms:**
- NodeClaim created, instance running, but no Node object
- Timeout after 15 minutes → NodeClaim deleted

**Debug Steps:**
```bash
# 1. Check NodeClaim status
kubectl describe nodeclaim <name>

# 2. Get instance ID
INSTANCE_ID=$(kubectl get nodeclaim <name> -o jsonpath='{.status.providerID}' | cut -d/ -f5)

# 3. Check instance console output
aws ec2 get-console-output --instance-id $INSTANCE_ID --output text

# 4. Common issues to look for in console output:
# - IMDSv1 vs IMDSv2 mismatch
# - Bootstrap script failures
# - SSM parameter access denied
# - Container runtime issues
```

**Common Root Causes:**
1. IAM instance profile permissions
2. Security group blocking kubelet communication
3. User data / bootstrap script errors
4. AMI compatibility issues

---

### 8.2 Excessive Consolidation / Node Churn

**Symptoms:**
- Nodes constantly being created and destroyed
- Pod restart storms
- High ECR data transfer costs

**Debug:**
```bash
# Enable debug logging
kubectl set env deployment/karpenter -n karpenter LOG_LEVEL=debug

# Watch consolidation decisions
kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter | grep consolidation

# Check disruption events
kubectl get events --all-namespaces --field-selector source=karpenter | grep -i disrupt
```

**Solutions:**
1. Increase `consolidateAfter`: 15m-30m
2. Add disruption budgets
3. Use `do-not-disrupt` annotation on critical pods
4. Check for rapid scaling workloads (HPA, CronJobs)
5. Consider separate NodePools for batch workloads

---

### 8.3 Pod Stuck in Pending After Node Creation

**Symptoms:**
- Karpenter creates node
- Pod nominated to node
- Pod never schedules

**Debug:**
```bash
# Check pod events
kubectl describe pod <name>

# Check node taints
kubectl get node <node-name> -o json | jq '.spec.taints'

# Verify pod tolerations
kubectl get pod <name> -o json | jq '.spec.tolerations'
```

**Common Causes:**
1. **Startup taints not removed:** CNI/CSI agents not running
2. **PodAntiAffinity conflicts:** Can't satisfy spreading
3. **Resource requests changed:** After nomination but before scheduling
4. **PVC topology mismatch:** Volume in wrong zone

---

## 9. Advanced Configurations

### 9.1 Multi-Tenant Isolation

```yaml
# Separate NodePool per team with taints
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: team-data-science
spec:
  template:
    metadata:
      labels:
        team: data-science
    spec:
      taints:
        - key: team
          value: data-science
          effect: NoSchedule
      requirements:
        # GPU instances
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["g5", "g6", "p4", "p5"]
```

**Pod Configuration:**
```yaml
spec:
  nodeSelector:
    team: data-science
  tolerations:
    - key: team
      operator: Equal
      value: data-science
      effect: NoSchedule
```

---

### 9.2 Batch Workload Pattern

```yaml
# Separate pool for batch jobs
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: batch-jobs
spec:
  disruption:
    consolidationPolicy: WhenEmpty  # Don't consolidate running jobs
    consolidateAfter: 30s  # Quick cleanup when empty
    budgets:
      - nodes: "100%"
        reasons: ["Empty"]  # Allow all empty nodes to be removed
      - nodes: "5%"
        reasons: ["Underutilized", "Drifted"]  # Very conservative for running jobs

  template:
    spec:
      expireAfter: 168h  # 7 days

      # Jobs don't need long termination grace
      terminationGracePeriod: 10m

      requirements:
        # Spot for cost savings
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]

        # Compute-optimized instances
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m"]
```

---

### 9.3 Stateful Workload Pattern

```yaml
# High-availability stateful services
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: stateful-services
spec:
  disruption:
    consolidationPolicy: WhenEmpty  # Never disrupt running stateful pods
    budgets:
      - nodes: "0%"  # Essentially disabled

  template:
    spec:
      expireAfter: 720h  # 30 days
      terminationGracePeriod: null  # Infinite - respect PDBs forever

      requirements:
        # On-demand for stability
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]

        # EBS-optimized instances
        - key: karpenter.k8s.aws/instance-family
          operator: In
          values: ["m5", "m6i", "m7i"]
```

**Pods should use:**
```yaml
metadata:
  annotations:
    karpenter.sh/do-not-disrupt: "true"
spec:
  # Topology spreading for HA
  topologySpreadConstraints:
    - maxSkew: 1
      topologyKey: topology.kubernetes.io/zone
      whenUnsatisfiable: DoNotSchedule
```

---

## 10. Known Bugs & Workarounds (Current)

### 10.1 v1.0-v1.3: "VPCIdNotSpecified" Error

**Issue:** [#7834](https://github.com/aws/karpenter-provider-aws/issues/7834) (36 reactions)
**Versions Affected:** v1.3.0
**Status:** Fixed in v1.3.1+
**Link:** https://github.com/aws/karpenter-provider-aws/issues/7834

**Error:**
```
api error VPCIdNotSpecified: No default VPC for this user.
GroupName is only supported for EC2-Classic and default VPC.
```

**Workaround:** Upgrade to v1.3.1 or later.

---

### 10.2 Pod Logs "TLS handshake error" Spam

**Issue:** [#6898](https://github.com/aws/karpenter-provider-aws/issues/6898) (51 reactions)
**Status:** Generally harmless but annoying
**Link:** https://github.com/aws/karpenter-provider-aws/issues/6898

**Cause:**
Kubernetes API server to webhook communication issue, likely cert caching in stdlib.

**Solutions:**
- Usually resolves itself
- Restart karpenter pods if persistent
- Not a functional issue - can be ignored

---

### 10.3 Consolidation Doesn't Replace On-Demand with Spot

**Issue:** [#7832](https://github.com/aws/karpenter-provider-aws/issues/7832) (6 reactions)
**Status:** Known limitation
**Link:** https://github.com/aws/karpenter-provider-aws/issues/7832

**Problem:**
When spot capacity becomes available after using on-demand, Karpenter doesn't automatically consolidate back to spot.

**Workaround:**
Enable spot-to-spot consolidation and set aggressive `expireAfter` to force refresh.

---

## 11. Community Resources & Support

### 11.1 Official Resources

- 📖 **Documentation:** https://karpenter.sh/
- 💬 **Slack:** [#karpenter on Kubernetes Slack](https://kubernetes.slack.com/archives/C02SFFZSA2K)
- 🐛 **GitHub Issues (AWS Provider):** https://github.com/aws/karpenter-provider-aws/issues
- 🐛 **GitHub Issues (Core):** https://github.com/kubernetes-sigs/karpenter/issues
- 🔄 **Upgrade Guide:** https://karpenter.sh/docs/upgrading/upgrade-guide/
- 📚 **Getting Started:** https://karpenter.sh/docs/getting-started/
- 🛠️ **Troubleshooting:** https://karpenter.sh/docs/troubleshooting/
- 📊 **Monitoring:** https://karpenter.sh/docs/reference/metrics/

### 11.2 Useful Community Tools

1. **Karpenter Dashboard:** Import Grafana dashboards from community
2. **Node Termination Handler:** [aws-node-termination-handler](https://github.com/aws/aws-node-termination-handler) - For comprehensive interruption handling
3. **kubectl-karpenter plugin:** For easier troubleshooting
4. **EKS Blueprints:** [terraform-aws-eks](https://github.com/terraform-aws-modules/terraform-aws-eks) includes Karpenter modules

### 11.3 AWS-Specific Resources

- [EKS Best Practices - Karpenter](https://aws.github.io/aws-eks-best-practices/karpenter/)
- [AWS Workshop - Karpenter](https://www.eksworkshop.com/docs/autoscaling/compute/karpenter/)
- [AWS Containers Roadmap](https://github.com/aws/containers-roadmap/issues?q=is%3Aissue+karpenter)
- [EKS Optimized AMIs](https://github.com/awslabs/amazon-eks-ami)

### 11.4 Getting Help

**When Opening Issues:**
1. Include full `kubectl get nodepool <name> -o yaml`
2. Include `kubectl get ec2nodeclass <name> -o yaml`
3. Provide Karpenter controller logs with relevant timeframe
4. Specify version: Chart, Karpenter, and Kubernetes
5. Describe expected vs actual behavior
6. Include pod specs for scheduling issues

---

## 12. Migration Decision Matrix

### Should You Migrate to Karpenter?

| Factor | Consider Karpenter | Stay with CAS |
|--------|-------------------|---------------|
| Cluster Size | >50 nodes | <20 nodes |
| Workload Type | Mixed, dynamic | Homogeneous, predictable |
| Cost Optimization | High priority | Not critical |
| Team Experience | Kubernetes-native tools | Prefer AWS-native |
| GitOps | Yes (with care) | No requirement |
| Spot Usage | Heavy (>50%) | Light (<30%) |
| Node Lifecycle | Need fine control | Simple is fine |

### Migration Readiness Checklist

- [ ] Team trained on Karpenter concepts
- [ ] Monitoring/alerting prepared
- [ ] Test environment available
- [ ] GitOps pipeline updated (if applicable)
- [ ] IAM policies reviewed and updated
- [ ] Subnet capacity verified (IP availability)
- [ ] PodDisruptionBudgets configured
- [ ] Rollback plan prepared
- [ ] Cost baseline established

---

## 13. Top 20 Issues by Community Impact

| Rank | Issue | Title | Reactions | Comments | Status |
|------|-------|-------|-----------|----------|--------|
| 1 | [#3798](https://github.com/aws/karpenter-provider-aws/issues/3798) | Warm Up Nodes/Hibernation | 185 👍 | 36 | Open |
| 2 | [#2394](https://github.com/aws/karpenter-provider-aws/issues/2394) | Scale storage based on ephemeral-storage | 180 👍 | 14 | Open |
| 3 | [kubernetes-sigs#749](https://github.com/kubernetes-sigs/karpenter/issues/749) | Manual node provisioning | 474 👍 | 83 | Open |
| 4 | [kubernetes-sigs#735](https://github.com/kubernetes-sigs/karpenter/issues/735) | consolidateAfter parameter | 244 👍 | 87 | Closed |
| 5 | [#1240](https://github.com/aws/karpenter-provider-aws/issues/1240) | Fleet allocation strategy | 162 👍 | 23 | Open |
| 6 | [kubernetes-sigs#750](https://github.com/kubernetes-sigs/karpenter/issues/750) | Node repair for NotReady | 152 👍 | 56 | Closed |
| 7 | [#5234](https://github.com/aws/karpenter-provider-aws/issues/5234) | Avoid subnets without IPs | 121 👍 | 23 | Open |
| 8 | [#4354](https://github.com/aws/karpenter-provider-aws/issues/4354) | AWS Warm Pools support | 122 👍 | 14 | Open |
| 9 | [#6818](https://github.com/aws/karpenter-provider-aws/issues/6818) | Webhook namespace hardcoded | 83 👍 | 23 | Closed |
| 10 | [#3324](https://github.com/aws/karpenter-provider-aws/issues/3324) | Placement group support | 85 👍 | 14 | Open |
| 11 | [#2813](https://github.com/aws/karpenter-provider-aws/issues/2813) | Rebalance Recommendation handling | 69 👍 | 18 | Open |
| 12 | [#6847](https://github.com/aws/karpenter-provider-aws/issues/6847) | ArgoCD v1.0 upgrade issues | 63 👍 | 95 | Closed |
| 13 | [#7146](https://github.com/aws/karpenter-provider-aws/issues/7146) | Excessive node churn | 54 👍 | 37 | Open |
| 14 | [#2921](https://github.com/aws/karpenter-provider-aws/issues/2921) | Subnet IP selection | 54 👍 | 29 | Open |
| 15 | [#7029](https://github.com/aws/karpenter-provider-aws/issues/7029) | NotReady nodes issue | 51 👍 | 31 | Open |
| 16 | [#6898](https://github.com/aws/karpenter-provider-aws/issues/6898) | TLS handshake errors v1.0.1 | 51 👍 | 47 | Closed |
| 17 | [#2259](https://github.com/aws/karpenter-provider-aws/issues/2259) | Savings plan support | 46 👍 | 18 | Open |
| 18 | [#5369](https://github.com/aws/karpenter-provider-aws/issues/5369) | EKS Access Entry API | 41 👍 | 19 | Open |
| 19 | [#7875](https://github.com/aws/karpenter-provider-aws/issues/7875) | IAM policy size limit | 36 👍 | 11 | Open |
| 20 | [#8155](https://github.com/aws/karpenter-provider-aws/issues/8155) | IMDSv2 for operator | 31 👍 | 13 | Open |

---

## 14. Key Takeaways & Recommendations

### For New Users:

1. **Start with v1.x** - v0.x is legacy
2. **Read the migration guide thoroughly** - breaking changes are significant
3. **Test in non-production first** - consolidation can be aggressive
4. **Use conservative settings initially:**
   - `consolidateAfter: 15m`
   - `budgets: 10%`
   - Pin AMI versions
5. **Implement comprehensive monitoring** before production

### For Existing Users:

1. **Upgrade to v1.x** - better stability and features
2. **Review consolidation settings** if experiencing node churn
3. **Implement disruption budgets** for production safety
4. **Pin AMI versions** to avoid surprise node issues
5. **Monitor subnet IP capacity** proactively

### For Cluster Operators:

1. **Establish clear NodePool strategy:**
   - System pool (karpenter itself, critical services)
   - General compute pool (most workloads)
   - Batch pool (short-lived jobs)
   - Stateful pool (databases, caches)

2. **Cost governance:**
   - Set appropriate resource limits
   - Use spot for non-critical workloads
   - Monitor cost per NodePool
   - Consider future cost limit features

3. **Operational excellence:**
   - Automate monitoring and alerting
   - Document incident response procedures
   - Maintain cost baseline metrics
   - Regular node refresh schedule

---

## 15. Upcoming Features to Watch

Based on issue discussions and maintainer activity:

1. **Subnet IP awareness** - Auto-detect available IPs ([#5234](https://github.com/aws/karpenter-provider-aws/issues/5234)) - Assigned
2. **Warm pools / Hibernation** ([#3798](https://github.com/aws/karpenter-provider-aws/issues/3798)) - High priority, no ETA
3. **Savings plan integration** ([#2259](https://github.com/aws/karpenter-provider-aws/issues/2259)) - Long-term
4. **Fleet allocation strategies** ([#1240](https://github.com/aws/karpenter-provider-aws/issues/1240)) - Awaiting evidence
5. **Node repair automation** ([kubernetes-sigs/karpenter#750](https://github.com/kubernetes-sigs/karpenter/issues/750)) - v1.x priority
6. **Dynamic storage scaling** ([#2394](https://github.com/aws/karpenter-provider-aws/issues/2394)) - v1.x priority
7. **Placement group support** ([#3324](https://github.com/aws/karpenter-provider-aws/issues/3324)) - Community interest
8. **Enhanced disruption controls** - Time-based, pod-aware

---

## 16. Breaking Changes History

### [v0.27](https://github.com/aws/karpenter-provider-aws/releases/tag/v0.27.0) (June 2023)
- Introduced consolidation feature
- Changed default deprovisioning behavior
- Release notes: https://github.com/aws/karpenter-provider-aws/releases/tag/v0.27.0

### [v0.32](https://github.com/aws/karpenter-provider-aws/releases/tag/v0.32.0) (February 2024)
- Introduced v1beta1 API
- Provisioner → NodePool
- AWSNodeTemplate → EC2NodeClass
- Release notes: https://github.com/aws/karpenter-provider-aws/releases/tag/v0.32.0

### [v1.0](https://github.com/aws/karpenter-provider-aws/releases/tag/v1.0.0) (August 2024) - MAJOR
- v1 API stable
- `expireAfter` behavior changed (no longer respects PDBs by default)
- Webhook conversion required for v1beta1 compatibility
- Separate karpenter-crd chart
- Helm chart namespace handling changes
- Release notes: https://github.com/aws/karpenter-provider-aws/releases/tag/v1.0.0
- **Migration guide:** https://karpenter.sh/docs/upgrading/upgrade-guide/

### [v1.3](https://github.com/aws/karpenter-provider-aws/releases/tag/v1.3.0) (October 2024)
- Multiple bug fixes
- Improved hash collision handling
- Security group resolution improvements
- Release notes: https://github.com/aws/karpenter-provider-aws/releases/tag/v1.3.0

### [v1.8](https://github.com/aws/karpenter-provider-aws/releases/tag/v1.8.0) (Latest - December 2025)
- Latest stable release
- Continued improvements and bug fixes
- Release notes: https://github.com/aws/karpenter-provider-aws/releases/tag/v1.8.0

---

## Conclusion

Karpenter has evolved into a production-ready autoscaler with powerful cost optimization capabilities. The community has identified clear patterns:

**Most Critical Issues:**
1. Node consolidation behavior (churn management)
2. Migration complexity (especially v1.0 upgrade)
3. Network resource limits (subnet IPs)

**Most Wanted Features:**
1. Warm pools / faster scaling
2. Savings plan awareness
3. Dynamic resource allocation

**Key Success Factors:**
1. Conservative initial configuration
2. Comprehensive monitoring
3. Gradual rollout with proper testing
4. Understanding disruption mechanics
5. Proper GitOps integration planning

The Karpenter maintainer team is highly responsive, with most critical bugs addressed within weeks. The community is active and helpful, with detailed troubleshooting available in GitHub issues.

---

**Document Version:** 1.0
**Last Updated:** December 10, 2025
**Contributors:** Community analysis of 393 open issues, 2000+ closed issues
**Repositories Analyzed:**
- [aws/karpenter-provider-aws](https://github.com/aws/karpenter-provider-aws) (393 open issues)
- [kubernetes-sigs/karpenter](https://github.com/kubernetes-sigs/karpenter) (Core framework)

**Useful Search Queries:**
- [All "consolidation" issues](https://github.com/aws/karpenter-provider-aws/issues?q=is%3Aissue+consolidation)
- [All "webhook" issues](https://github.com/aws/karpenter-provider-aws/issues?q=is%3Aissue+webhook)
- [All "migration" issues](https://github.com/aws/karpenter-provider-aws/issues?q=is%3Aissue+migration)
- [All "NotReady" issues](https://github.com/aws/karpenter-provider-aws/issues?q=is%3Aissue+NotReady)
