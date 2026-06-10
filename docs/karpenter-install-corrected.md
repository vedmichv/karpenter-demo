# Installing Karpenter on EKS — Corrected & Annotated Guide

> **Purpose.** A workshop/handout circulated for installing Karpenter is based on
> outdated steps that **will fail on current Karpenter (1.12.x)**. This document
> is the corrected, end-to-end procedure, with an explicit call-out of *what was
> wrong in the original and why*, so you can follow it confidently and understand
> the changes.
>
> **Verified against:** Karpenter `v1.12.1` (the current release at time of
> writing), canonical AWS getting-started guide, and a live deployment in
> `eu-north-1`. Karpenter moves fast — always cross-check the official
> [Getting Started](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/)
> page for the version you actually install.

---

## TL;DR — What was wrong in the original instructions

| # | Original step | Problem | Correct approach |
|---|---------------|---------|------------------|
| 1 | **Repo `aws/karpenter` for "latest"** (`api.github.com/repos/aws/karpenter/releases/latest`) | Minor: the provider repo was renamed to **`aws/karpenter-provider-aws`**. The old path currently **redirects** and still returns the right tag, so this alone won't break — but the canonical name is what the docs use. | Query `aws/karpenter-provider-aws/releases/latest`. |
| 2 | **CloudFormation pinned to `v1.9.0`** while `KARPENTER_VERSION=latest` | Version drift: the IAM template is from 1.9 but the chart you install is 1.12 → IAM and controller expectations diverge. | Pin the CloudFormation template to **the same `${KARPENTER_VERSION}`** you install. |
| 3 | **Region/account via IMDS** (`http://169.254.169.254/...`) | IMDS only exists on EC2/Cloud9. **It does not exist in CloudShell, your laptop, or most CI** — the script hangs or sets empty vars and every later step misfires. | Set `AWS_DEFAULT_REGION` explicitly; get account via `aws sts get-caller-identity`. |
| 4 | **`--attach-policy-arn .../KarpenterControllerPolicy-${CLUSTER_NAME}`** | **This single policy no longer exists.** Since Karpenter 1.x the controller policy was split into **5–6 scoped managed policies**. This step fails with `NoSuchEntity`. | Let CloudFormation create the scoped policies and attach them via the cluster config (shown below). |
| 5 | **IRSA flow** (`associate-iam-oidc-provider` + `create iamserviceaccount`) + **manual `aws-auth`** | Still works, but it is the legacy path and is the most error-prone part of the handout. Modern EKS uses **EKS Pod Identity**, which removes the OIDC provider and the manual `aws-auth` edit entirely. | Use **Pod Identity** (primary path below). IRSA kept as an appendix. |
| 6 | **Helm: `serviceAccount.annotations.eks.amazonaws.com/role-arn=...`, `settings.clusterEndpoint=...`, `featureGates.spotToSpotConsolidation=true`** | • The SA role-arn annotation is **IRSA-only** — not used with Pod Identity.<br>• **`settings.clusterEndpoint` is no longer required.**<br>• Spot-to-Spot consolidation is **GA** — the feature gate is obsolete. | Drop all three. Use `settings.clusterName`, `settings.interruptionQueue`, and (new in 1.12) `settings.enableZonalShift`. |

> **Bottom line:** the original is a mix of three different Karpenter generations.
> Steps 4 and 6 break outright on 1.12; steps 1–3 cause silent drift. Follow the
> corrected procedure below.

---

## Prerequisites

- AWS CLI **v2**, `kubectl`, `eksctl`, `helm` v3+ installed and on `PATH`.
- Credentials for the **correct account**: `aws sts get-caller-identity` should
  show the account you intend to use. (If you juggle multiple Isengard/SSO
  accounts, confirm this first — wrong-account is the #1 silent failure.)
- Permissions to create EKS clusters, IAM roles/policies, and CloudFormation stacks.

---

## Step 1 — Environment variables (no IMDS)

```bash
export KARPENTER_NAMESPACE="kube-system"
export AWS_PARTITION="aws"                 # aws-cn / aws-us-gov if applicable
export AWS_DEFAULT_REGION="eu-north-1"      # <-- set explicitly; do NOT rely on IMDS
export ENABLE_ZONAL_SHIFT="true"            # new in 1.12; set false to opt out
export CLUSTER_NAME="karpenter-demo"        # name your cluster
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Latest Karpenter version — use the canonical repository name:
KARPENTER_VERSION_V=$(curl -sL "https://api.github.com/repos/aws/karpenter-provider-aws/releases/latest" | jq -r ".tag_name")
export KARPENTER_VERSION="${KARPENTER_VERSION_V#v}"   # strip leading 'v'

# Kubernetes version for the AMI alias lookup (pick a supported EKS version):
export K8S_VERSION="1.32"

echo "Karpenter: ${KARPENTER_VERSION} | Cluster: ${CLUSTER_NAME} | Region: ${AWS_DEFAULT_REGION} | Account: ${AWS_ACCOUNT_ID}"
```

> ❌ **Original mistake:** region/account were read from
> `http://169.254.169.254/...` (IMDS). That endpoint is unreachable off-EC2 — in
> CloudShell or on a laptop the variables come back empty and every subsequent
> `aws`/`eksctl` call targets the wrong place. Always set the region explicitly.
>
> ℹ️ **Minor:** `releases/latest` was queried from `aws/karpenter` (the old repo).
> It currently redirects and returns the correct tag, so it won't break on its own —
> but `aws/karpenter-provider-aws` is the canonical name used by the docs.

---

## Step 2 — Create IAM resources (CloudFormation) — pin to the SAME version

```bash
TEMPOUT="$(mktemp)"
curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > "${TEMPOUT}"

aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}" \
  --region "${AWS_DEFAULT_REGION}"
```

This creates the node role (`KarpenterNodeRole-${CLUSTER_NAME}`), the interruption
SQS queue, and the **scoped controller policies**. On 1.12 these are:

```
KarpenterControllerEKSIntegrationPolicy-${CLUSTER_NAME}
KarpenterControllerIAMIntegrationPolicy-${CLUSTER_NAME}
KarpenterControllerInterruptionPolicy-${CLUSTER_NAME}
KarpenterControllerNodeLifecyclePolicy-${CLUSTER_NAME}
KarpenterControllerResourceDiscoveryPolicy-${CLUSTER_NAME}
KarpenterControllerZonalShiftPolicy-${CLUSTER_NAME}     # added in 1.12
```

> ❌ **Original mistake:** the template URL was hard-pinned to `v1.9.0` while you
> install "latest". Pin it to `v${KARPENTER_VERSION}` so IAM matches the chart.
> Also note there is **no single `KarpenterControllerPolicy`** anymore — see Step 3.

---

## Step 3 — Create the cluster with EKS Pod Identity (primary path)

This single `eksctl` config creates the cluster, wires the controller's IAM via
**Pod Identity**, maps the node role, and installs the Pod Identity agent — no
OIDC provider, no manual `aws-auth` edit.

```bash
eksctl create cluster -f - <<EOF
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "${K8S_VERSION}"
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}

iam:
  withOIDC: true
  podIdentityAssociations:
  - namespace: "${KARPENTER_NAMESPACE}"
    serviceAccountName: karpenter
    roleName: ${CLUSTER_NAME}-karpenter
    permissionPolicyARNs:
    - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerNodeLifecyclePolicy-${CLUSTER_NAME}
    - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerIAMIntegrationPolicy-${CLUSTER_NAME}
    - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerEKSIntegrationPolicy-${CLUSTER_NAME}
    - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerInterruptionPolicy-${CLUSTER_NAME}
    - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerResourceDiscoveryPolicy-${CLUSTER_NAME}

iamIdentityMappings:
- arn: "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
  username: system:node:{{EC2PrivateDNSName}}
  groups:
  - system:bootstrappers
  - system:nodes

managedNodeGroups:
- instanceType: m5.large
  amiFamily: AmazonLinux2023
  name: ${CLUSTER_NAME}-ng
  desiredCapacity: 2
  minSize: 1
  maxSize: 10

zonalShiftConfig:
  enabled: ${ENABLE_ZONAL_SHIFT}

addons:
- name: eks-pod-identity-agent
EOF

export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.endpoint" --output text)"
export KARPENTER_IAM_ROLE_ARN="arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter"
```

> ❌ **Original mistakes folded into this one step:**
> - `eksctl create iamidentitymapping` + manual `aws-auth` edit → replaced by the
>   `iamIdentityMappings:` block (and unnecessary for the controller with Pod Identity).
> - `associate-iam-oidc-provider` + `create iamserviceaccount --attach-policy-arn
>   .../KarpenterControllerPolicy-...` → **that policy doesn't exist**; Pod Identity
>   attaches the scoped policies directly via `permissionPolicyARNs`.
>
> *(Prefer the legacy IRSA flow? See [Appendix A](#appendix-a--irsa-alternative).)*

---

## Step 4 — Create the EC2 Spot service-linked role (first time per account)

```bash
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com 2>/dev/null || true
```

Already exists → you'll see `has been taken in this account`; the `|| true`
makes that harmless.

---

## Step 5 — Install Karpenter via Helm

```bash
helm registry logout public.ecr.aws 2>/dev/null || true

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set "settings.enableZonalShift=${ENABLE_ZONAL_SHIFT}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait
```

> ❌ **Original mistakes:**
> - `--set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"=...` — IRSA-only;
>   **omit with Pod Identity**.
> - `--set settings.clusterEndpoint=...` — **no longer required**; remove it.
> - `--set settings.featureGates.spotToSpotConsolidation=true` — Spot-to-Spot
>   consolidation is **GA**; the feature gate is obsolete. Use `settings.enableZonalShift`
>   instead (the relevant 1.12 toggle).

---

## Step 6 — Verify

```bash
# Pods: expect two karpenter pods Running
kubectl get pods -n "${KARPENTER_NAMESPACE}" -l app.kubernetes.io/name=karpenter

# Deployment: 2/2
kubectl get deploy karpenter -n "${KARPENTER_NAMESPACE}"

# Confirm the running image matches the version you installed
kubectl get deploy karpenter -n "${KARPENTER_NAMESPACE}" \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'

# Helm release
helm list -n "${KARPENTER_NAMESPACE}"

# Pod Identity association exists for the karpenter SA
aws eks list-pod-identity-associations --cluster-name "${CLUSTER_NAME}" \
  --region "${AWS_DEFAULT_REGION}" --query 'associations[].[namespace,serviceAccount]' --output text
```

Expected: two `karpenter-*` pods `Running`, deployment `2/2`, image tag ==
`${KARPENTER_VERSION}`, and a `kube-system / karpenter` Pod Identity association.

---

## Step 7 — NodePool & EC2NodeClass (current `v1` API)

Karpenter needs at least one `NodePool` + `EC2NodeClass` before it provisions nodes.
On 1.12 the **stable APIs** are `karpenter.sh/v1` and `karpenter.k8s.aws/v1`
(older guides used `v1beta1`/`v1alpha5` — those are obsolete).

```bash
cat <<EOF | envsubst | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  amiSelectorTerms:
    - alias: "al2023@latest"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot", "on-demand"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["4"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
EOF

kubectl get nodepools
kubectl get ec2nodeclasses
```

---

## Appendix A — IRSA alternative (legacy, if you cannot use Pod Identity)

Pod Identity (Step 3) is recommended. If your environment mandates IRSA, replace
Step 3 with the cluster create **without** `podIdentityAssociations`, then:

```bash
# 1. OIDC provider
eksctl utils associate-iam-oidc-provider --cluster "${CLUSTER_NAME}" --approve

# 2. IAM service account bound to the SCOPED policies (NOT a single policy)
eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" --name karpenter --namespace "${KARPENTER_NAMESPACE}" \
  --role-name "${CLUSTER_NAME}-karpenter" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerNodeLifecyclePolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerIAMIntegrationPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerEKSIntegrationPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerInterruptionPolicy-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerResourceDiscoveryPolicy-${CLUSTER_NAME}" \
  --role-only --approve

export KARPENTER_IAM_ROLE_ARN="arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter"

# 3. Map the node role into aws-auth
eksctl create iamidentitymapping \
  --cluster "${CLUSTER_NAME}" \
  --arn "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --username system:node:{{EC2PrivateDNSName}} \
  --group system:bootstrappers --group system:nodes
```

Then in the Helm install (Step 5) **add** the IRSA annotation:

```bash
  --set serviceAccount.annotations."eks\.amazonaws\.com/role-arn"="${KARPENTER_IAM_ROLE_ARN}"
```

> Even here, note the fix: attach the **five scoped policies**, never the
> non-existent single `KarpenterControllerPolicy-${CLUSTER_NAME}`.

---

## Appendix B — Gotchas worth flagging to participants

- **Wrong AWS account / region** is the most common "nothing works" cause. Run
  `aws sts get-caller-identity` and confirm `AWS_DEFAULT_REGION` before anything.
  Symptom of wrong account: `aws eks list-clusters` returns empty while `kubectl`
  still works (kubeconfig has its own token).
- **CloudShell / laptop have no IMDS.** Any script reading `169.254.169.254` will
  hang or set empty vars. Set region/account explicitly (Step 1).
- **Version pinning.** Keep the CloudFormation template tag and the Helm
  `--version` identical. Mixing 1.9 IAM with a 1.12 chart causes subtle failures.
- **`al2023@latest` AMI alias.** Preferred over hard-coded AMI IDs; Karpenter
  resolves the current EKS-optimized AL2023 image automatically.
- **eks-node-viewer / k9s** referenced in the original are optional visualization
  tools, not part of the install. Install them only if you want the dashboards.

---

*Maintained in the `karpenter-demo` repository. Re-verify against the official
Karpenter getting-started page for the exact version you install — Karpenter's
IAM and settings surface changes between minor releases.*
