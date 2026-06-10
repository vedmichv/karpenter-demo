# Karpenter Workshop — Companion & Fix Guide (Install + Basic NodePool)

> **Purpose.** This is a client-facing companion to the AWS Karpenter workshop
> (*Install Karpenter* and *Basic NodePool* sections). It is based on a **live run
> of the actual workshop**, not on assumptions. The workshop **does complete
> end-to-end**, but it pins its IAM to an old Karpenter version while installing
> the *latest* chart — which causes **one silent failure** (interruption
> health-checks are disabled) — plus several smaller outdated-but-harmless bits and
> one typo. Below: exactly what to skip, what to change, and why.

> **Verified live on the workshop environment (2026-06-10):**
> EKS `workshop-cluster`, region `us-east-1`, Kubernetes **1.31**, Karpenter chart
> resolved to **1.12.1**, IDE = EC2-backed code-server (`/home/ec2-user`).
> Every claim below was reproduced in that terminal.

---

## TL;DR — the one thing that matters

The workshop installs **Karpenter 1.12.1** but creates its IAM role from the
**v1.9.0** CloudFormation template. Karpenter 1.12 needs a permission that the 1.9
policy does not grant. Result: the install looks green (pods `Running`, Helm
`deployed`), but the controller logs this error on a loop:

```
"level":"ERROR" "controller":"interruption.instancestatus"
"message":"ec2:DescribeInstanceStatus permission is not allowed, update the IAM
policy and restart the Karpenter deployment to enable instance status health checks"
"aws-error-code":"UnauthorizedOperation" ... StatusCode: 403
User: ...assumed-role/workshop-cluster-karpenter is not authorized to perform:
ec2:DescribeInstanceStatus
```

**Impact:** Karpenter runs and provisions nodes fine, but **instance-status health
checks are silently disabled** — Karpenter won't proactively replace
degraded/unhealthy EC2 instances. Easy to miss during a demo; bites later.

**The fix (pick one), detailed below:** match the IAM template version to the chart
version. That's the root cause; everything else in the workshop works.

---

## What actually happens at each step (live results)

| Step | Workshop does | Live result | Verdict |
|------|---------------|-------------|---------|
| **1. Env vars** | reads region via **IMDS** (`169.254.169.254`); `KARPENTER_VERSION` = latest from `aws/karpenter` | IMDS **works** (EC2 IDE); version resolved to **1.12.1** | ✅ Fine **on this IDE**. ⚠️ IMDS only — see note 1 |
| **2. CloudFormation IAM** | template pinned to **`v1.9.0`** (`/docs/` path) | HTTP 200; stack created; makes a **single** `KarpenterControllerPolicy-<cluster>` | ✅ Runs — but it's the **old** policy (root cause of the bug) |
| **3. aws-auth mapping** | `eksctl create iamidentitymapping` | `STEP3_EXIT=0`, node role added | ✅ Works |
| **4. OIDC + IRSA role** | `associate-iam-oidc-provider` + `create iamserviceaccount` attaching the single policy | `STEP4_EXIT=0`, role `…-karpenter` created | ✅ Works — single policy **does** exist on 1.9 |
| **5. Spot SLR** | `create-service-linked-role` | idempotent | ✅ Works |
| **6. Helm install** | chart `${KARPENTER_VERSION}` (=1.12.1) with IRSA annotation, `clusterEndpoint`, `spotToSpotConsolidation` | `HELM_EXIT=0`, `STATUS: deployed`, 2 pods `1/1 Running` | ⚠️ Installs, but controller logs the **403** above |
| **7–10. ns / dir / eks-node-viewer / k9s** | helper tooling | — | ✅ Fine |

**Bottom line:** the workshop is internally consistent (1.9 IAM template + step-4
single-policy match), so nothing errors out loudly. The only real problem is the
**version drift** between the pinned IAM (1.9) and the installed chart (1.12),
which silently disables one feature.

---

## The fix

You have two clean options. **Option A is recommended** (keep latest Karpenter).

### Option A — Pin the IAM template to the SAME version as the chart (recommended)

In **Step 2**, change the CloudFormation template URL from the hard-coded `v1.9.0`
to the version you're actually installing. Replace the step-2 command with:

```bash
# KARPENTER_VERSION is already set in step 1 (e.g. 1.12.1)
TEMPOUT=$(mktemp)
curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > "${TEMPOUT}" \
&& aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"
```

Two things change vs. the workshop:
- `refs/tags/v1.9.0` → `v${KARPENTER_VERSION}` (matches the chart).
- path `/docs/` → `/preview/` (the `/docs/` path is the old layout; `/preview/` is
  current and is what resolves for recent tags).

The 1.12 template grants `ec2:DescribeInstanceStatus` (and other newer
permissions), so the 403 disappears. **Note:** the 1.12 template splits the
controller policy into several scoped managed policies instead of one
`KarpenterControllerPolicy`. So **Step 4 must attach those**, not the single
policy — use this step-4 service-account command instead:

```bash
eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve

eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" --name karpenter --namespace "${KARPENTER_NAMESPACE}" \
  --role-name "${CLUSTER_NAME}-karpenter" \
  --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerNodeLifecyclePolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerIAMIntegrationPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerEKSIntegrationPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerInterruptionPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:aws:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerResourceDiscoveryPolicy-${CLUSTER_NAME}" \
  --role-only --approve

export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter"
```

> If a `KarpenterControllerZonalShiftPolicy-${CLUSTER_NAME}` is also created by your
> template version, attach it too (it appears in 1.12).

### Option B — Keep the workshop as-is, just pin the chart to match the IAM

If you'd rather not touch steps 2 and 4, pin the **chart** down to the 1.9 line in
step 1 so it matches the IAM template:

```bash
export KARPENTER_VERSION="1.9.0"   # instead of 'latest'
```

Simpler (one line), but you run an older Karpenter. Fine for a workshop; not what
you'd ship to production.

### Already installed and seeing the 403? Patch in place

If you already ran the workshop verbatim and want to fix the live cluster without
reinstalling, re-deploy the matching CloudFormation template (Option A's step-2
command), then attach the new policies to the existing role and restart:

```bash
kubectl rollout restart deployment/karpenter -n kube-system
```

---

## Notes & gotchas (smaller, but worth telling participants)

1. **IMDS (step 1) works *here*, but is environment-specific.** This workshop IDE
   is an **EC2** instance, so `curl http://169.254.169.254/...` returns the region
   fine. The same step **fails in AWS CloudShell or on a laptop** (no IMDS) — the
   variables come back empty and later steps misfire. If you run the steps outside
   the provided IDE, set the region explicitly instead:
   ```bash
   export AWS_DEFAULT_REGION=us-east-1
   ```

2. **Old Helm flags are accepted but stale.** Step 6 still passes
   `--set settings.clusterEndpoint=...` and
   `--set settings.featureGates.spotToSpotConsolidation=true`. On 1.12 the chart
   **accepts them without error**, so the install succeeds — but `clusterEndpoint`
   is no longer required and Spot-to-Spot consolidation is **GA** (the feature gate
   is obsolete). Harmless to leave; cleaner to drop. The current toggle is
   `--set settings.enableZonalShift=true`.

3. **IRSA vs Pod Identity.** The workshop uses **IRSA** (OIDC provider +
   `iamserviceaccount` + `aws-auth`). That's fine and it works. Modern EKS prefers
   **EKS Pod Identity**, which removes the OIDC step and the `aws-auth` edit. For a
   workshop on an existing cluster the difference is a couple of commands and not
   worth deviating — **stay on the workshop's IRSA path**. (If you ever build a
   cluster from scratch, prefer Pod Identity: add the `eks-pod-identity-agent`
   addon and a `podIdentityAssociations` block, and drop the IRSA annotation from
   the Helm install.)

4. **`aws/karpenter` repo name (step 1).** The latest-version query uses the old
   `aws/karpenter` repo. It currently **redirects** to
   `aws/karpenter-provider-aws` and returns the right tag, so it doesn't break —
   but the canonical name is `aws/karpenter-provider-aws`.

5. **IAM is locked down in the workshop account.** The IDE role intentionally lacks
   `iam:ListPolicies` (you'll get `AccessDenied` if you try to list). Use
   `aws iam get-policy --policy-arn <arn>` to check a specific policy instead of
   listing.

---

## Verify the install is actually healthy

After installing, don't just trust "pods Running" — check the controller log for
the 403:

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=karpenter
kubectl get deploy karpenter -n kube-system \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'   # should match KARPENTER_VERSION

# This should return NOTHING once the IAM is correct:
kubectl logs -n kube-system -l app.kubernetes.io/name=karpenter -c controller --tail=200 \
  | grep -i 'DescribeInstanceStatus\|UnauthorizedOperation' || echo "OK — no IAM permission errors"
```

Healthy = two pods `1/1 Running`, image tag matches the version you installed, and
the `grep` prints `OK — no IAM permission errors`.

---

# Basic NodePool section

After installing Karpenter you create a `NodePool` + `EC2NodeClass`, then scale an
app to watch Karpenter provision a node. Verified live: it **works and really
provisions an EC2 instance** — but the workshop's NodeClass manifest has a **typo**
that will break it, and there's an ordering gotcha. Fixes below.

## What actually happens (live results)

| Step | Workshop does | Live result | Verdict |
|------|---------------|-------------|---------|
| Deploy NodePool | `kubectl apply` a `karpenter.sh/v1` NodePool | created, `READY=True` | ✅ Works |
| Deploy EC2NodeClass | `kubectl create` a `karpenter.k8s.aws/v1` NodeClass with `role: karpenterNodeRole-…` | typo in role name → see below | ⚠️ Typo + `create` |
| Scale app 0→5 | deploy `inflate` (1 CPU each) into ns `workshop`, scale to 5 | Karpenter launched **c6a.2xlarge** on-demand, node Ready ~60s, 5/5 pods Running | ✅ Works once the fixes are applied |

## Fix 1 — the NodeClass `role` typo (this one breaks provisioning)

The workshop's `default-nodeclass.yaml` has:

```yaml
  role: karpenterNodeRole-${CLUSTER_NAME}    # ❌ lowercase 'k'
```

The actual IAM role created by the CloudFormation stack is
**`KarpenterNodeRole-…`** (capital **K**) — confirmed with
`aws iam get-role --role-name KarpenterNodeRole-${CLUSTER_NAME}`. With the
lowercase name, Karpenter cannot resolve the instance profile and the NodeClass
never becomes ready / no nodes launch. **Use the correct capitalization:**

```yaml
  role: KarpenterNodeRole-${CLUSTER_NAME}    # ✅ capital 'K'
```

## Fix 2 — create the `workshop` namespace first

The `inflate` deployment targets `namespace: workshop`. That namespace is created
in **Install Karpenter step 7** (`kubectl create namespace workshop`). If you
jumped straight from install to Basic NodePool you'll get
`namespaces "workshop" not found` and the deploy silently does nothing (0 pods, 0
nodes). Create it before deploying:

```bash
kubectl create namespace workshop
```

## Fix 3 — `kubectl create` → `apply` (minor)

The NodeClass step uses `kubectl create -f default-nodeclass.yaml`. That fails with
`AlreadyExists` if you re-run it (e.g. after fixing the typo). Use
`kubectl apply -f` so the step is idempotent.

## Verify provisioning actually worked

```bash
kubectl get nodeclaim                       # expect one, READY=True
kubectl get nodes -l eks-immersion-team=my-team \
  -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type
kubectl get pods -n workshop                # all replicas Running, not Pending
```

Healthy = a NodeClaim `READY=True`, one Karpenter node (e.g. `c6a.2xlarge`,
`on-demand`), and every `inflate` pod `Running`. If pods stay `Pending`, check the
NodeClass `role` typo (Fix 1) and the controller logs.

> **Note on terminal entry:** the workshop manifests are pasted as multi-line
> heredocs. If you paste them through an automation/clipboard that collapses
> newlines, the YAML breaks. Pasting by hand in the IDE terminal is fine; for
> scripted entry, write the file in one step (e.g. base64-decode) instead of a
> multi-line heredoc.

---

# Limit Resources subsection — works as documented (one cosmetic log change)

The `limits: cpu: "10"` on the NodePool behaves **exactly** as the workshop
describes. Scaling `inflate` to 12 replicas: Karpenter adds a second node
(`c6a.large`, 2 vCPU) on top of the existing `c6a.2xlarge` (8 vCPU), reaches the
10-vCPU cap, and leaves the remaining pods `Pending`. Verified live: **8 Running /
4 Pending**, two on-demand nodes. No fix needed — the lesson lands as written.

**Only divergence — the controller log wording changed (cosmetic).** The workshop
shows a 2024 log line (commit `62a726c`). On 1.12.1 the `message` field is
unchanged, but the `error` string is reworded:

| field | text |
|-------|------|
| `message` (both) | `could not schedule pod` |
| `error` — workshop (old) | `all available instance types exceed limits for nodepool: "default"` |
| `error` — 1.12.1 (live) | `all available instance types exceed limits for nodepool (NodePool=default)` |

So a check that greps for `exceed limits` still works; one that greps the exact old
suffix `nodepool: "default"` will silently match nothing. Use the version-agnostic
form:

```bash
kubectl -n "${KARPENTER_NAMESPACE}" logs -l app.kubernetes.io/name=karpenter \
  -c controller --tail=500 | grep -i 'exceed limits'
```

> The workshop prose also paraphrases the log as
> `Could not schedule pod, all available instance types exceed nodepool limits` —
> that exact sentence is **not** in the JSON logs (it merges the two fields above).
> Don't grep for it verbatim.

---

# Disruption subsection — works as documented (set timing expectations)

`consolidationPolicy: WhenEmpty` + `consolidateAfter: 30s` behaves exactly as the
workshop describes. Scaling `inflate` to 0 → Karpenter empties and removes **both**
of its nodes, leaving only the original cluster nodes. Verified live: after the
scale-down, `kubectl get nodeclaim` → `No resources found`, `kubectl get nodes
-l eks-immersion-team=my-team` → `No resources found`, and the total node count
dropped back to the **3** baseline nodes — precisely what the workshop predicts.
No fix needed.

**One expectation to set for participants — "30s" is not "gone in 30 seconds".**
`consolidateAfter: 30s` is only the *idle wait* before Karpenter decides a node is
disruptable. The full removal then adds: the consolidation reconcile, `tainted
node` (cordon), pod drain, EC2 terminate, and finally `deleted node` / `deleted
nodeclaim`. End-to-end this took **a few minutes** on the live cluster (two nodes,
removed sequentially), not 30 seconds. If you're demoing, scale to 0 and keep
talking — don't refresh `eks-node-viewer` expecting an instant drop, or you'll look
like it's broken when it's just working through the queue.

**Log wording changed on 1.12.1 — the workshop's grep finds nothing.** This is the
real divergence in this subsection. The workshop tells you to look for
`disrupting nodeclaim(s) via delete` and shows a `marking consolidatable` line.
Verified live on 1.12.1:

| Workshop says to look for | Live on 1.12.1 | Note |
|---------------------------|----------------|------|
| `marking consolidatable` (DEBUG) | **not present** | Karpenter logs at **INFO** by default; this is a `DEBUG` line, so you never see it unless you lower the log level |
| `disrupting nodeclaim(s) via delete, terminating N nodes ... reason:"empty"` | **`disrupting node(s)`** (INFO) | message was **renamed**; the `terminating … / reason` text is no longer in this field |
| `tainted node` | `tainted node` | ✅ verbatim |
| `deleted node` | `deleted node` | ✅ verbatim |
| `deleted nodeclaim` | `deleted nodeclaim` | ✅ verbatim |

So a participant grepping `disrupting nodeclaim` (the workshop's exact phrase) gets
**zero hits** and thinks disruption didn't happen — when it did. Use a version-safe
grep that matches the lifecycle messages that *are* stable:

```bash
kubectl -n "${KARPENTER_NAMESPACE}" logs -l app.kubernetes.io/name=karpenter \
  -c controller --tail=-1 | grep -iE 'disrupting node|deleted node|deleted nodeclaim'
```

> Tip: the `--tail` in the workshop's example can be too small — by the time you
> run it, the `disrupting node(s)` line may have scrolled out of a short tail.
> Use `--tail=-1` (full log) or `--since=20m` when hunting for it.

---

# RightSizing subsection — works perfectly (one broken `cd`)

The right-sizing demo behaves **exactly** as the workshop describes. Deploying
`inflate` at 8 replicas with `requests: cpu=1, memory=1Gi` each, Karpenter launches
two correctly-sized nodes and packs the pods optimally. Verified live:

| | Workshop says | Live result |
|--|---------------|-------------|
| Nodes | `c6a.2xlarge` + `c6a.large` | **`c6a.2xlarge` + `c6a.large`** ✅ |
| Packing | 7 pods on the 2xlarge, 1 on the large | **7 on `c6a.2xlarge`, 1 on `c6a.large`** ✅ |
| Pods | all Running | **8/8 Running** ✅ |

**Fix 1 — `cd ~/environment/karpenter` fails (no such directory).** Step 1.B opens
with:

```bash
cd ~/environment/karpenter      # ❌ this directory does not exist
cat <<EoF> basic-rightsizing.yaml
...
```

There is **no `karpenter` subfolder** — the workshop's manifests live directly in
`~/environment` (`default-nodepool.yaml`, `default-nodeclass.yaml`,
`basic-deploy.yaml`). Verified: `ls ~/environment/karpenter` →
`No such file or directory`. The `cd` errors out, but the shell **keeps going** and
the heredoc writes `basic-rightsizing.yaml` into whatever directory you were in —
usually fine, but confusing, and a copy-paste of the whole block leaves you unsure
where the file landed. **Just drop the `cd`** (or `cd ~/environment` first) and
write the file there:

```bash
cd ~/environment
cat <<EoF> basic-rightsizing.yaml
... (manifest unchanged) ...
EoF
kubectl apply -f basic-rightsizing.yaml
```

**Logs — all verbatim on 1.12.1 (no change).** Unlike the Disruption section, the
provisioning log messages the workshop shows are still exact on 1.12.1:
`found provisionable pod(s)`, `computed new nodeclaim(s) to fit pod(s)`,
`created nodeclaim` (with `requests` + `instance-types`), `launched nodeclaim`. The
`instance-types` field still reads like `c3.2xlarge, c4.2xlarge, ... and N
other(s)`. The only one you **won't** see is `marking consolidatable` — it's
`DEBUG`, same as noted in the Disruption section.

---

# Drift subsection — works, but has 3 copy-paste bugs + changed log

Drift is the longest subsection and it **does work end-to-end** on 1.12.1: create an
`oldnode` EC2NodeClass pinned to a K8s-1.30 AMI, point the NodePool at it, launch a
v1.30 node, then create a `newnode` class with a 1.31 AMI and re-point the NodePool.
Karpenter marks the old node drifted, launches a v1.31 replacement, and terminates
the old one. Verified live: started on **v1.30.14**, ended with a single
**v1.31.14** node Ready, old node gone. ✅

But the workshop's manifests repeat the **same bugs from earlier sections**, twice
each, plus the verification log has changed.

**Fix 1 — `role: karpenterNodeRole-$CLUSTER_NAME` typo (BOTH classes).** Same typo
as the Basic NodePool section, and it appears in **both** `oldnode_class.yaml` and
`newnode_class.yaml`. Lowercase `k` → the node never launches. Must be
**`KarpenterNodeRole-$CLUSTER_NAME`** (capital K) in both.

**Fix 2 — `cd ~/environment/karpenter` fails (×3 here).** Same missing directory as
RightSizing — the Drift section `cd`s into it **three times** (before
`oldnode_class.yaml`, `drift-deploy.yaml`, and `newnode_class.yaml`), and again in
cleanup. The directory doesn't exist; drop the `cd` (or `cd ~/environment`).

**Fix 3 — `kubectl -f oldnode_class.yaml create` (wrong flag order, ×2).** The
classes are applied with `kubectl -f <file> create`. The correct form is
`kubectl create -f <file>` — and `kubectl apply -f <file>` is better (idempotent on
re-run). Applies to both `oldnode_class.yaml` and `newnode_class.yaml`.

**The drift log changed (workshop's example won't match field-for-field).** The
workshop shows (2024, commit `6174c75`):

```
"message":"disrupting nodeclaim(s) via replace, terminating 1 nodes (5 pods) .../c6a.2xlarge/on-demand and replacing with ...", "reason":"drifted"
```

Live on 1.12.1 the same event is split into separate fields:

| 1.12.1 field | value |
|--------------|-------|
| `message` | `disrupting node(s)` |
| `controller` | `disruption` |
| `decision` | `replace` |
| `disrupted-node-count` | `1` |

The `reason":"drifted"` suffix and the `via replace, terminating N nodes (...)` prose
are **gone** from the message. The line still contains the substring `drift`
elsewhere, so the workshop's `... | grep -i drift | jq` **does still return it** —
but if you eyeball it for the exact 2024 wording you won't find it. The lesson
(drift → replace) is intact; only the log shape moved.

> **Harmless transient during drift:** while the replacement is in flight you may
> see a few `"Reconciler error" ... "no subnets found"` lines (controller
> `nodeclass.status`, error `getting drift, calculating ami drift, ...`). On the
> live run these stopped the moment the new node registered (last occurrence ~7 min
> before the cluster settled) — it's retry noise during the cutover, not a failure.
> Don't flag it to participants as a problem unless it **keeps** repeating after the
> v1.31 node is Ready.

**Cleanup works as written** (modulo the same `cd ~/environment/karpenter` →
drop it): re-point the NodePool to the `default` EC2NodeClass, delete `oldnode` and
`newnode`, delete the `inflate` deployment, remove the manifest files.

---

*Maintained in the `karpenter-demo` repository. Re-verify against the official
[Karpenter Getting Started](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
for the exact version you install — Karpenter's IAM surface changes between minor
releases, which is exactly what causes the drift documented here.*
