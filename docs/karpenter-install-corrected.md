# Karpenter Workshop — "Install Karpenter" Companion & Fix Guide

> **Purpose.** This is a client-facing companion to the AWS *"Install Karpenter"*
> workshop page. It is based on a **live run of the actual workshop**, not on
> assumptions. The workshop **does complete end-to-end**, but it pins its IAM to an
> old Karpenter version while installing the *latest* chart — which causes **one
> silent failure** (interruption health-checks are disabled) plus a few
> outdated-but-harmless bits. Below: exactly what to skip, what to change, and why.

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

*Maintained in the `karpenter-demo` repository. Re-verify against the official
[Karpenter Getting Started](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
for the exact version you install — Karpenter's IAM surface changes between minor
releases, which is exactly what causes the drift documented here.*
