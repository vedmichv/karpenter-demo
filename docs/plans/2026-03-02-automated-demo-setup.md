# Automated Karpenter Demo Setup - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure karpenter-demo repo with modular bash scripts and Claude Code commands that automate creating two EKS clusters (basic + highload) with Karpenter, monitoring, and kubectl context setup.

**Architecture:** Modular bash scripts in `scripts/` handle each concern (prereqs, cluster creation, karpenter install, monitoring, contexts, teardown). A master `setup-all.sh` orchestrates them for standalone use. Claude Code custom commands in `.claude/commands/` provide interactive orchestration with version checking from karpenter.sh. All cluster-specific values in manifests use envsubst templates.

**Tech Stack:** Bash, eksctl, helm, kubectl, AWS CLI v2, envsubst, kustomize

---

### Task 1: Clean up old files and create directory structure

**Files:**
- Delete: all old directories and files (karpenter-demo01/, cluster-autoscaler/, vscode-instances/, cloud9-config.md, CONFIG_REVIEW.md, KARPENTER_COMMUNITY_ANALYSIS.md, KARPENTER_DEPLOYMENT_GUIDE.md, and all -2026* duplicate files)
- Create: new directory structure

**Step 1: Remove old directories and files**

```bash
cd /Users/vedmich/Documents/GitHub/vedmich/karpenter-demo

# Remove old directories
rm -rf karpenter-demo01/
rm -rf cluster-autoscaler/
rm -rf vscode-instances/
rm -rf kube-ops-view/
rm -rf high-load/deploy/
rm -rf deploy/

# Remove old docs
rm -f cloud9-config.md
rm -f CONFIG_REVIEW.md
rm -f KARPENTER_COMMUNITY_ANALYSIS.md
rm -f KARPENTER_DEPLOYMENT_GUIDE.md

# Remove all duplicate -2026* timestamp files
find . -name '*-2026*' -type f -delete
find . -name '*-2026*' -type d -exec rm -rf {} + 2>/dev/null || true
```

**Step 2: Create new directory structure**

```bash
mkdir -p scripts
mkdir -p manifests/basic
mkdir -p manifests/highload
mkdir -p manifests/monitoring/kube-ops-view
mkdir -p high-load
mkdir -p .claude/commands
mkdir -p docs/plans
```

**Step 3: Verify structure**

Run: `find . -type d | grep -v '.git/' | grep -v node_modules | sort`
Expected: shows scripts/, manifests/basic/, manifests/highload/, manifests/monitoring/kube-ops-view/, high-load/, .claude/commands/, docs/plans/

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: remove old files, create new directory structure"
```

---

### Task 2: Create config.env

**Files:**
- Create: `config.env`

**Step 1: Create config.env**

```bash
# config.env - Default configuration for Karpenter demo setup
# Override any variable by exporting it before running scripts

# AWS
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-north-1}"
AWS_PARTITION="${AWS_PARTITION:-aws}"

# Kubernetes
K8S_VERSION="${K8S_VERSION:-1.34}"

# Cluster naming: kd-basic-YY-MM-DD / kd-hl-YY-MM-DD
CLUSTER_PREFIX="${CLUSTER_PREFIX:-kd}"
BASIC_CLUSTER_SUFFIX="${BASIC_CLUSTER_SUFFIX:-basic}"
HIGHLOAD_CLUSTER_SUFFIX="${HIGHLOAD_CLUSTER_SUFFIX:-hl}"

# Managed NodeGroup
MNG_INSTANCE_TYPE="${MNG_INSTANCE_TYPE:-c5.2xlarge}"
MNG_MIN_SIZE="${MNG_MIN_SIZE:-1}"
MNG_MAX_SIZE="${MNG_MAX_SIZE:-10}"
MNG_DESIRED_SIZE="${MNG_DESIRED_SIZE:-2}"

# Karpenter
KARPENTER_VERSION_FALLBACK="${KARPENTER_VERSION_FALLBACK:-1.8.2}"
KARPENTER_NAMESPACE="${KARPENTER_NAMESPACE:-kube-system}"
```

**Step 2: Verify syntax**

Run: `bash -n config.env`
Expected: no output (no syntax errors)

**Step 3: Commit**

```bash
git add config.env
git commit -m "feat: add config.env with default configuration"
```

---

### Task 3: Create scripts/lib.sh (shared library)

**Files:**
- Create: `scripts/lib.sh`

**Step 1: Write lib.sh**

```bash
#!/usr/bin/env bash
# lib.sh - Shared functions for karpenter-demo scripts
# Source this file: source "$(dirname "$0")/lib.sh"

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
log_step()  { echo -e "\n${GREEN}==>${NC} ${BLUE}$*${NC}"; }

# Load config.env from repo root
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_config() {
  if [[ -f "${REPO_ROOT}/config.env" ]]; then
    # shellcheck disable=SC1091
    source "${REPO_ROOT}/config.env"
  else
    log_error "config.env not found at ${REPO_ROOT}/config.env"
    exit 1
  fi
}

# Generate cluster name with today's date
# Usage: generate_cluster_name "basic" -> "kd-basic-26-03-02"
generate_cluster_name() {
  local suffix="$1"
  local date_str
  date_str=$(date +"%y-%m-%d")
  echo "${CLUSTER_PREFIX}-${suffix}-${date_str}"
}

# Wait for a command to succeed with timeout
# Usage: wait_for "kubectl get nodes" 300
wait_for() {
  local cmd="$1"
  local timeout="${2:-120}"
  local interval="${3:-5}"
  local elapsed=0

  while ! eval "$cmd" &>/dev/null; do
    if [[ $elapsed -ge $timeout ]]; then
      log_error "Timed out waiting for: $cmd"
      return 1
    fi
    sleep "$interval"
    elapsed=$((elapsed + interval))
  done
  return 0
}

# Check if a command exists
require_cmd() {
  if ! command -v "$1" &>/dev/null; then
    log_error "Required command not found: $1"
    return 1
  fi
}
```

**Step 2: Validate**

Run: `bash -n scripts/lib.sh && echo "OK"`
Expected: `OK`

Run: `shellcheck scripts/lib.sh || true`
Expected: no major errors (SC1091 is expected and disabled)

**Step 3: Commit**

```bash
git add scripts/lib.sh
git commit -m "feat: add scripts/lib.sh shared library"
```

---

### Task 4: Create scripts/check-prereqs.sh

**Files:**
- Create: `scripts/check-prereqs.sh`

**Step 1: Write check-prereqs.sh**

```bash
#!/usr/bin/env bash
# check-prereqs.sh - Verify all required tools are installed
source "$(dirname "$0")/lib.sh"
load_config

log_step "Checking prerequisites"

ERRORS=0

for cmd in kubectl eksctl helm aws; do
  if require_cmd "$cmd"; then
    local_ver=$("$cmd" version --short 2>/dev/null || "$cmd" version 2>/dev/null | head -1 || "$cmd" --version 2>/dev/null | head -1)
    log_ok "$cmd: ${local_ver}"
  else
    ERRORS=$((ERRORS + 1))
  fi
done

# Check AWS credentials
log_info "Checking AWS credentials..."
if aws sts get-caller-identity &>/dev/null; then
  AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
  log_ok "AWS Account: ${AWS_ACCOUNT_ID}"
else
  log_error "AWS credentials not configured. Run 'aws configure' or set AWS_PROFILE"
  ERRORS=$((ERRORS + 1))
fi

# Check region
log_info "Region: ${AWS_DEFAULT_REGION}"

if [[ $ERRORS -gt 0 ]]; then
  log_error "${ERRORS} prerequisite(s) missing. Install them and retry."
  exit 1
fi

log_ok "All prerequisites satisfied"
```

**Step 2: Make executable and validate**

Run: `chmod +x scripts/check-prereqs.sh && bash -n scripts/check-prereqs.sh && echo "OK"`
Expected: `OK`

**Step 3: Commit**

```bash
git add scripts/check-prereqs.sh
git commit -m "feat: add prerequisites checker script"
```

---

### Task 5: Create scripts/get-latest-karpenter.sh

**Files:**
- Create: `scripts/get-latest-karpenter.sh`

**Step 1: Write get-latest-karpenter.sh**

```bash
#!/usr/bin/env bash
# get-latest-karpenter.sh - Fetch latest Karpenter version from karpenter.sh
# Outputs the version string (e.g., "1.8.2") to stdout
source "$(dirname "$0")/lib.sh"
load_config

# Try to get latest version from GitHub releases API (most reliable)
get_from_github() {
  curl -fsSL "https://api.github.com/repos/aws/karpenter-provider-aws/releases/latest" 2>/dev/null \
    | grep '"tag_name"' \
    | sed -E 's/.*"v([^"]+)".*/\1/'
}

# Try to get from Helm OCI registry
get_from_helm() {
  helm show chart oci://public.ecr.aws/karpenter/karpenter 2>/dev/null \
    | grep '^version:' \
    | awk '{print $2}'
}

VERSION=""

# Method 1: GitHub releases
VERSION=$(get_from_github)

# Method 2: Helm registry
if [[ -z "$VERSION" ]]; then
  log_warn "GitHub API failed, trying Helm registry..." >&2
  VERSION=$(get_from_helm)
fi

# Fallback to config
if [[ -z "$VERSION" ]]; then
  log_warn "Could not fetch latest version, using fallback: ${KARPENTER_VERSION_FALLBACK}" >&2
  VERSION="${KARPENTER_VERSION_FALLBACK}"
fi

echo "$VERSION"
```

**Step 2: Make executable and validate**

Run: `chmod +x scripts/get-latest-karpenter.sh && bash -n scripts/get-latest-karpenter.sh && echo "OK"`
Expected: `OK`

**Step 3: Commit**

```bash
git add scripts/get-latest-karpenter.sh
git commit -m "feat: add script to fetch latest Karpenter version"
```

---

### Task 6: Create all manifest files

**Files:**
- Create: `manifests/basic/nodepool-simple.yaml`
- Create: `manifests/basic/nodepool-ondemand.yaml`
- Create: `manifests/basic/nodepool-spot.yaml`
- Create: `manifests/basic/ec2nodeclass.yaml.tpl`
- Create: `manifests/basic/inflate-10pods.yaml`
- Create: `manifests/basic/inflate-600pods-split.yaml`
- Create: `manifests/highload/nodepool-spot.yaml`
- Create: `manifests/highload/ec2nodeclass.yaml.tpl`
- Create: `manifests/highload/deployment-template.yaml`

**Step 1: Create manifests/basic/nodepool-simple.yaml**

This is the single NodePool used at start (both spot and on-demand):

```yaml
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
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
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
    cpu: 5000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1s
```

**Step 2: Create manifests/basic/nodepool-ondemand.yaml**

For the split demo (50/50 spot and on-demand):

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: on-demand
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: capacity-spread
          operator: In
          values:
            - "1"
            - "2"
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: 500
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1s
```

**Step 3: Create manifests/basic/nodepool-spot.yaml**

```yaml
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: spot
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: capacity-spread
          operator: In
          values:
            - "3"
            - "4"
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: 500
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1s
```

**Step 4: Create manifests/basic/ec2nodeclass.yaml.tpl**

Template with envsubst variables — no hardcoded values:

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  amiSelectorTerms:
    - alias: "al2023@${ALIAS_VERSION}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
```

**Step 5: Create manifests/basic/inflate-10pods.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 10
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: inflate
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
```

**Step 6: Create manifests/basic/inflate-600pods-split.yaml**

For the split load demo with topology spreading:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: inflate
spec:
  replicas: 600
  selector:
    matchLabels:
      app: inflate
  template:
    metadata:
      labels:
        app: inflate
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - name: inflate
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
          resources:
            requests:
              cpu: "250m"
              memory: "256Mi"
      topologySpreadConstraints:
        - maxSkew: 1
          topologyKey: capacity-spread
          whenUnsatisfiable: DoNotSchedule
          labelSelector:
            matchLabels:
              app: inflate
```

**Step 7: Create manifests/highload/nodepool-spot.yaml**

```yaml
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
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: 5000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1s
```

**Step 8: Create manifests/highload/ec2nodeclass.yaml.tpl**

```yaml
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  kubelet:
    maxPods: 200
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  amiSelectorTerms:
    - alias: "al2023@${ALIAS_VERSION}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
```

**Step 9: Create manifests/highload/deployment-template.yaml**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: "${NAME}"
spec:
  replicas: ${BATCH}
  selector:
    matchLabels:
      app: "${NAME}"
  template:
    metadata:
      labels:
        app: "${NAME}"
    spec:
      terminationGracePeriodSeconds: 0
      containers:
        - image: public.ecr.aws/eks-distro/kubernetes/pause:3.7
          name: "${NAME}"
          resources:
            requests:
              cpu: "${CPU}"
              memory: "${MEM}"
      tolerations:
        - key: karpenter
          operator: Exists
      nodeSelector:
        karpenter.sh/capacity-type: spot
```

**Step 10: Verify all manifests have valid YAML syntax**

Run: `for f in manifests/basic/*.yaml manifests/highload/*.yaml; do echo "Checking $f..."; python3 -c "import yaml; yaml.safe_load(open('$f'))" && echo "OK"; done`
Expected: all files report OK (skip .tpl files — they have envsubst vars)

**Step 11: Commit**

```bash
git add manifests/
git commit -m "feat: add all Karpenter manifest templates (basic + highload)"
```

---

### Task 7: Create monitoring manifests (kube-ops-view)

**Files:**
- Create: `manifests/monitoring/kube-ops-view/kustomization.yaml`
- Create: `manifests/monitoring/kube-ops-view/deployment.yaml`
- Create: `manifests/monitoring/kube-ops-view/service.yaml`
- Create: `manifests/monitoring/kube-ops-view/redis-deployment.yaml`
- Create: `manifests/monitoring/kube-ops-view/redis-service.yaml`
- Create: `manifests/monitoring/kube-ops-view/rbac.yaml`

**Step 1: Create all kube-ops-view manifests**

These are the same as the existing files. Copy them verbatim from the existing kube-ops-view/deploy/ directory content (already read above). The `service.yaml` uses LoadBalancer type with `loadBalancerSourceRanges` for security.

Files are:
- `kustomization.yaml`: lists all resources
- `deployment.yaml`: kube-ops-view container (hjacobs/kube-ops-view:20.4.0) with redis backend
- `service.yaml`: LoadBalancer on port 80->8080 with IP restriction
- `redis-deployment.yaml`: redis:5-alpine backend
- `redis-service.yaml`: ClusterIP for redis on port 6379
- `rbac.yaml`: ServiceAccount, ClusterRole (list nodes/pods, get metrics), ClusterRoleBinding

All file contents are identical to the existing files already read above. Write them to the new paths.

**Step 2: Verify kustomize build**

Run: `kubectl kustomize manifests/monitoring/kube-ops-view/ > /dev/null && echo "OK"`
Expected: `OK` (validates kustomize structure)

**Step 3: Commit**

```bash
git add manifests/monitoring/
git commit -m "feat: add kube-ops-view monitoring manifests"
```

---

### Task 8: Create high-load scripts

**Files:**
- Create: `high-load/create-workload.sh`
- Create: `high-load/delete-workload.sh`

**Step 1: Create high-load/create-workload.sh**

Adapted from existing — uses manifests/highload/deployment-template.yaml:

```bash
#!/usr/bin/env bash
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
TEMPLATE="${REPO_ROOT}/manifests/highload/deployment-template.yaml"

# total amount of pods to create
TOTAL=${1:-500}
# deploy size
export BATCH=${2:-100}
export NAMESPACE=${3:-default}

echo "Performance test: create"
echo "- ${TOTAL} pods, ${BATCH} batch in ${NAMESPACE} namespace"

CPU_OPTIONS=(250m 500m 750m 1 2)
MEM_OPTIONS=(128M 256M 512M 750M 1G)

CPU_OPTIONS_LENG=${#CPU_OPTIONS[@]}
MEM_OPTIONS_LENG=${#MEM_OPTIONS[@]}

COUNT=0
while (test $COUNT -lt $TOTAL); do
  RAND=$(LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c 5)
  export CPU=${CPU_OPTIONS[$((RANDOM % CPU_OPTIONS_LENG))]}
  export MEM=${MEM_OPTIONS[$((RANDOM % MEM_OPTIONS_LENG))]}
  CPU_LOWER=$(echo "$CPU" | tr '[:upper:]' '[:lower:]')
  MEM_LOWER=$(echo "$MEM" | tr '[:upper:]' '[:lower:]')
  export NAME="batch-${CPU_LOWER}-${MEM_LOWER}-${RAND}"
  echo "Creating ${NAME} with ${BATCH} replicas"
  envsubst < "${TEMPLATE}" | kubectl apply -n "${NAMESPACE}" -f -
  COUNT=$((COUNT + BATCH))
done
```

**Step 2: Create high-load/delete-workload.sh**

```bash
#!/usr/bin/env bash
set -eo pipefail

echo "Deleting all batch deployments..."
kubectl get deploy | grep batch | awk '{print $1}' | xargs kubectl delete deploy
echo "Done."
```

**Step 3: Make executable and validate**

Run: `chmod +x high-load/create-workload.sh high-load/delete-workload.sh && bash -n high-load/create-workload.sh && bash -n high-load/delete-workload.sh && echo "OK"`
Expected: `OK`

**Step 4: Commit**

```bash
git add high-load/
git commit -m "feat: add high-load workload scripts"
```

---

### Task 9: Create scripts/create-cluster.sh

**Files:**
- Create: `scripts/create-cluster.sh`

**Step 1: Write create-cluster.sh**

This script creates one EKS cluster. Takes cluster type as argument.

```bash
#!/usr/bin/env bash
# create-cluster.sh - Create one EKS cluster with Karpenter prerequisites
# Usage: ./create-cluster.sh <basic|highload> [cluster-name]
source "$(dirname "$0")/lib.sh"
load_config

CLUSTER_TYPE="${1:?Usage: $0 <basic|highload> [cluster-name]}"
case "$CLUSTER_TYPE" in
  basic)    SUFFIX="${BASIC_CLUSTER_SUFFIX}" ;;
  highload) SUFFIX="${HIGHLOAD_CLUSTER_SUFFIX}" ;;
  *)        log_error "Unknown cluster type: $CLUSTER_TYPE. Use 'basic' or 'highload'"; exit 1 ;;
esac

export CLUSTER_NAME="${2:-$(generate_cluster_name "$SUFFIX")}"
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
export KARPENTER_VERSION="${KARPENTER_VERSION:?KARPENTER_VERSION must be set}"

log_step "Creating cluster: ${CLUSTER_NAME} (type: ${CLUSTER_TYPE})"
log_info "Region: ${AWS_DEFAULT_REGION}"
log_info "K8s version: ${K8S_VERSION}"
log_info "Karpenter version: ${KARPENTER_VERSION}"

# Step 1: CloudFormation stack for Karpenter IAM
log_step "Deploying CloudFormation stack: Karpenter-${CLUSTER_NAME}"
TEMPOUT="$(mktemp)"
curl -fsSL "https://raw.githubusercontent.com/aws/karpenter-provider-aws/v${KARPENTER_VERSION}/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml" > "${TEMPOUT}"

aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}" \
  --region "${AWS_DEFAULT_REGION}"

rm -f "${TEMPOUT}"
log_ok "CloudFormation stack deployed"

# Step 2: Create EKS cluster
log_step "Creating EKS cluster: ${CLUSTER_NAME}"
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
    - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}

iamIdentityMappings:
- arn: "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
  username: system:node:{{EC2PrivateDNSName}}
  groups:
  - system:bootstrappers
  - system:nodes

managedNodeGroups:
- instanceType: ${MNG_INSTANCE_TYPE}
  amiFamily: AmazonLinux2023
  name: ${CLUSTER_NAME}-ng
  desiredCapacity: ${MNG_DESIRED_SIZE}
  minSize: ${MNG_MIN_SIZE}
  maxSize: ${MNG_MAX_SIZE}

addons:
- name: eks-pod-identity-agent
EOF

log_ok "Cluster ${CLUSTER_NAME} created"

# Step 3: Create Spot service-linked role (idempotent)
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com 2>/dev/null || true

# Output cluster info
export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.endpoint" --output text)"
log_ok "Cluster endpoint: ${CLUSTER_ENDPOINT}"
echo "${CLUSTER_NAME}"
```

**Step 2: Make executable and validate**

Run: `chmod +x scripts/create-cluster.sh && bash -n scripts/create-cluster.sh && echo "OK"`
Expected: `OK`

**Step 3: Commit**

```bash
git add scripts/create-cluster.sh
git commit -m "feat: add EKS cluster creation script"
```

---

### Task 10: Create scripts/install-karpenter.sh

**Files:**
- Create: `scripts/install-karpenter.sh`

**Step 1: Write install-karpenter.sh**

This installs Karpenter and applies NodePool + EC2NodeClass manifests.

```bash
#!/usr/bin/env bash
# install-karpenter.sh - Install Karpenter and apply manifests on current context
# Usage: ./install-karpenter.sh <basic|highload> <cluster-name> <karpenter-version>
source "$(dirname "$0")/lib.sh"
load_config

CLUSTER_TYPE="${1:?Usage: $0 <basic|highload> <cluster-name> <karpenter-version>}"
export CLUSTER_NAME="${2:?Cluster name required}"
export KARPENTER_VERSION="${3:?Karpenter version required}"

log_step "Installing Karpenter ${KARPENTER_VERSION} on ${CLUSTER_NAME} (${CLUSTER_TYPE})"

# Ensure we're on the right context
CURRENT_CONTEXT=$(kubectl config current-context)
log_info "Current kubectl context: ${CURRENT_CONTEXT}"

# Logout from ECR to avoid auth issues
helm registry logout public.ecr.aws 2>/dev/null || true

# Install Karpenter via Helm
log_step "Deploying Karpenter Helm chart"
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

log_ok "Karpenter Helm chart installed"

# Get ALIAS_VERSION for EC2NodeClass template
export AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity --query Account --output text)}"
export ALIAS_VERSION
ALIAS_VERSION="$(aws ssm get-parameter \
  --name "/aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2023/x86_64/standard/recommended/image_id" \
  --query Parameter.Value --output text \
  | xargs aws ec2 describe-images --query 'Images[0].Name' --image-ids \
  | sed -r 's/^.*(v[[:digit:]]+).*$/\1/')"

log_info "AMI alias version: ${ALIAS_VERSION}"

# Apply manifests based on cluster type
MANIFESTS_DIR="${REPO_ROOT}/manifests/${CLUSTER_TYPE}"

# Apply EC2NodeClass (template)
log_step "Applying EC2NodeClass"
envsubst < "${MANIFESTS_DIR}/ec2nodeclass.yaml.tpl" | kubectl apply -f -

# Apply NodePool
if [[ "$CLUSTER_TYPE" == "basic" ]]; then
  log_step "Applying basic NodePool (spot + on-demand)"
  kubectl apply -f "${MANIFESTS_DIR}/nodepool-simple.yaml"
elif [[ "$CLUSTER_TYPE" == "highload" ]]; then
  log_step "Applying highload NodePool (spot only, maxPods: 200)"
  kubectl apply -f "${MANIFESTS_DIR}/nodepool-spot.yaml"
fi

log_ok "Karpenter fully configured on ${CLUSTER_NAME}"

# Verify
log_step "Verifying Karpenter pods"
kubectl get pods -n "${KARPENTER_NAMESPACE}" -l app.kubernetes.io/name=karpenter
```

**Step 2: Make executable and validate**

Run: `chmod +x scripts/install-karpenter.sh && bash -n scripts/install-karpenter.sh && echo "OK"`
Expected: `OK`

**Step 3: Commit**

```bash
git add scripts/install-karpenter.sh
git commit -m "feat: add Karpenter installation script"
```

---

### Task 11: Create scripts/deploy-monitoring.sh

**Files:**
- Create: `scripts/deploy-monitoring.sh`

**Step 1: Write deploy-monitoring.sh**

```bash
#!/usr/bin/env bash
# deploy-monitoring.sh - Deploy metrics-server and kube-ops-view
source "$(dirname "$0")/lib.sh"

log_step "Deploying monitoring stack"

# Step 1: metrics-server
log_info "Installing metrics-server..."
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
log_ok "metrics-server deployed"

# Step 2: kube-ops-view
log_info "Installing kube-ops-view..."
kubectl apply -k "${REPO_ROOT}/manifests/monitoring/kube-ops-view"
log_ok "kube-ops-view deployed"

# Wait for kube-ops-view to become ready
log_info "Waiting for kube-ops-view pods..."
kubectl wait --for=condition=ready pod -l application=kube-ops-view,component=frontend --timeout=120s 2>/dev/null || true

# Get LoadBalancer URL
log_info "Getting kube-ops-view URL (may take a minute for ELB)..."
KOV_URL=""
for i in $(seq 1 30); do
  KOV_URL=$(kubectl get svc kube-ops-view -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)
  if [[ -n "$KOV_URL" ]]; then
    break
  fi
  sleep 5
done

if [[ -n "$KOV_URL" ]]; then
  log_ok "kube-ops-view URL: http://${KOV_URL}"
  echo "$KOV_URL"
else
  log_warn "LoadBalancer URL not yet available. Check with: kubectl get svc kube-ops-view"
fi
```

**Step 2: Make executable and validate**

Run: `chmod +x scripts/deploy-monitoring.sh && bash -n scripts/deploy-monitoring.sh && echo "OK"`
Expected: `OK`

**Step 3: Commit**

```bash
git add scripts/deploy-monitoring.sh
git commit -m "feat: add monitoring deployment script"
```

---

### Task 12: Create scripts/setup-contexts.sh

**Files:**
- Create: `scripts/setup-contexts.sh`

**Step 1: Write setup-contexts.sh**

```bash
#!/usr/bin/env bash
# setup-contexts.sh - Rename kubectl contexts to short aliases
# Usage: ./setup-contexts.sh <basic-cluster-name> <highload-cluster-name>
source "$(dirname "$0")/lib.sh"

BASIC_CLUSTER="${1:?Usage: $0 <basic-cluster-name> <highload-cluster-name>}"
HIGHLOAD_CLUSTER="${2:?Usage: $0 <basic-cluster-name> <highload-cluster-name>}"

log_step "Setting up kubectl contexts"

# Find the long eksctl context names
BASIC_CONTEXT=$(kubectl config get-contexts -o name | grep "${BASIC_CLUSTER}" | head -1)
HIGHLOAD_CONTEXT=$(kubectl config get-contexts -o name | grep "${HIGHLOAD_CLUSTER}" | head -1)

if [[ -z "$BASIC_CONTEXT" ]]; then
  log_error "Context for ${BASIC_CLUSTER} not found"
  exit 1
fi

if [[ -z "$HIGHLOAD_CONTEXT" ]]; then
  log_error "Context for ${HIGHLOAD_CLUSTER} not found"
  exit 1
fi

# Rename to short aliases
log_info "Renaming '${BASIC_CONTEXT}' -> 'kd-basic'"
kubectl config rename-context "${BASIC_CONTEXT}" kd-basic

log_info "Renaming '${HIGHLOAD_CONTEXT}' -> 'kd-hl'"
kubectl config rename-context "${HIGHLOAD_CONTEXT}" kd-hl

log_ok "Contexts configured:"
echo ""
echo "  Switch to basic cluster:    kubectl config use-context kd-basic"
echo "  Switch to highload cluster: kubectl config use-context kd-hl"
echo ""
echo "  Or use separate kubeconfigs per terminal:"
echo "    aws eks update-kubeconfig --name ${BASIC_CLUSTER} --region ${AWS_DEFAULT_REGION} --kubeconfig ~/.kube/config-basic"
echo "    aws eks update-kubeconfig --name ${HIGHLOAD_CLUSTER} --region ${AWS_DEFAULT_REGION} --kubeconfig ~/.kube/config-highload"
echo ""
echo "  Then in each terminal:"
echo "    export KUBECONFIG=~/.kube/config-basic   # Terminal 1"
echo "    export KUBECONFIG=~/.kube/config-highload # Terminal 2"
```

**Step 2: Make executable and validate**

Run: `chmod +x scripts/setup-contexts.sh && bash -n scripts/setup-contexts.sh && echo "OK"`
Expected: `OK`

**Step 3: Commit**

```bash
git add scripts/setup-contexts.sh
git commit -m "feat: add kubectl context setup script"
```

---

### Task 13: Create scripts/teardown.sh

**Files:**
- Create: `scripts/teardown.sh`

**Step 1: Write teardown.sh**

```bash
#!/usr/bin/env bash
# teardown.sh - Delete one or both demo clusters
# Usage: ./teardown.sh <cluster-name> [cluster-name-2]
source "$(dirname "$0")/lib.sh"
load_config

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <cluster-name> [cluster-name-2]"
  echo ""
  echo "Example: $0 kd-basic-26-03-02 kd-hl-26-03-02"
  exit 1
fi

delete_cluster() {
  local cluster_name="$1"
  log_step "Deleting cluster: ${cluster_name}"

  # Switch context
  local ctx
  ctx=$(kubectl config get-contexts -o name | grep "${cluster_name}" | head -1) || true
  if [[ -n "$ctx" ]]; then
    kubectl config use-context "$ctx"

    # Delete monitoring
    log_info "Removing monitoring..."
    kubectl delete -k "${REPO_ROOT}/manifests/monitoring/kube-ops-view" 2>/dev/null || true
    kubectl delete -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml 2>/dev/null || true

    # Delete Karpenter NodePools and EC2NodeClass
    log_info "Removing Karpenter resources..."
    kubectl delete nodepools --all 2>/dev/null || true
    kubectl delete ec2nodeclasses --all 2>/dev/null || true

    # Uninstall Karpenter
    log_info "Uninstalling Karpenter Helm chart..."
    helm uninstall karpenter --namespace "${KARPENTER_NAMESPACE}" 2>/dev/null || true
  fi

  # Delete CloudFormation stack
  log_info "Deleting CloudFormation stack: Karpenter-${cluster_name}"
  aws cloudformation delete-stack --stack-name "Karpenter-${cluster_name}" --region "${AWS_DEFAULT_REGION}" 2>/dev/null || true

  # Clean up launch templates
  log_info "Cleaning up launch templates..."
  aws ec2 describe-launch-templates \
    --filters "Name=tag:karpenter.k8s.aws/cluster,Values=${cluster_name}" \
    --region "${AWS_DEFAULT_REGION}" 2>/dev/null \
    | jq -r ".LaunchTemplates[].LaunchTemplateName" 2>/dev/null \
    | xargs -I{} aws ec2 delete-launch-template --launch-template-name {} --region "${AWS_DEFAULT_REGION}" 2>/dev/null || true

  # Delete EKS cluster
  log_info "Deleting EKS cluster: ${cluster_name}"
  eksctl delete cluster --name "${cluster_name}" --region "${AWS_DEFAULT_REGION}"

  # Clean up kubectl context
  kubectl config delete-context "kd-basic" 2>/dev/null || true
  kubectl config delete-context "kd-hl" 2>/dev/null || true

  log_ok "Cluster ${cluster_name} deleted"
}

for cluster in "$@"; do
  delete_cluster "$cluster"
done

log_ok "Teardown complete"
```

**Step 2: Make executable and validate**

Run: `chmod +x scripts/teardown.sh && bash -n scripts/teardown.sh && echo "OK"`
Expected: `OK`

**Step 3: Commit**

```bash
git add scripts/teardown.sh
git commit -m "feat: add cluster teardown script"
```

---

### Task 14: Create scripts/setup-all.sh (master script)

**Files:**
- Create: `scripts/setup-all.sh`

**Step 1: Write setup-all.sh**

```bash
#!/usr/bin/env bash
# setup-all.sh - Create both demo clusters with Karpenter and monitoring
# Standalone version (no Claude needed)
# Usage: ./setup-all.sh [karpenter-version]
source "$(dirname "$0")/lib.sh"
load_config

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Step 1: Check prerequisites
"${SCRIPT_DIR}/check-prereqs.sh"

# Step 2: Get Karpenter version
if [[ -n "${1:-}" ]]; then
  export KARPENTER_VERSION="$1"
  log_info "Using provided Karpenter version: ${KARPENTER_VERSION}"
else
  log_step "Fetching latest Karpenter version..."
  export KARPENTER_VERSION
  KARPENTER_VERSION=$("${SCRIPT_DIR}/get-latest-karpenter.sh")
  log_ok "Latest Karpenter version: ${KARPENTER_VERSION}"
fi

# Step 3: Generate cluster names
BASIC_CLUSTER=$(generate_cluster_name "${BASIC_CLUSTER_SUFFIX}")
HIGHLOAD_CLUSTER=$(generate_cluster_name "${HIGHLOAD_CLUSTER_SUFFIX}")

log_step "Will create clusters:"
log_info "  Basic:    ${BASIC_CLUSTER}"
log_info "  Highload: ${HIGHLOAD_CLUSTER}"
echo ""
read -r -p "Proceed? [Y/n] " response
if [[ "${response,,}" == "n" ]]; then
  log_info "Aborted."
  exit 0
fi

export AWS_ACCOUNT_ID
AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"

# Step 4: Create clusters (sequentially — eksctl doesn't parallelize well)
"${SCRIPT_DIR}/create-cluster.sh" basic "${BASIC_CLUSTER}"
"${SCRIPT_DIR}/create-cluster.sh" highload "${HIGHLOAD_CLUSTER}"

# Step 5: Install Karpenter on basic cluster
log_step "Switching to basic cluster"
kubectl config use-context "$(kubectl config get-contexts -o name | grep "${BASIC_CLUSTER}" | head -1)"
"${SCRIPT_DIR}/install-karpenter.sh" basic "${BASIC_CLUSTER}" "${KARPENTER_VERSION}"

# Step 6: Install Karpenter on highload cluster
log_step "Switching to highload cluster"
kubectl config use-context "$(kubectl config get-contexts -o name | grep "${HIGHLOAD_CLUSTER}" | head -1)"
"${SCRIPT_DIR}/install-karpenter.sh" highload "${HIGHLOAD_CLUSTER}" "${KARPENTER_VERSION}"

# Step 7: Deploy monitoring on both
log_step "Deploying monitoring on basic cluster"
kubectl config use-context "$(kubectl config get-contexts -o name | grep "${BASIC_CLUSTER}" | head -1)"
BASIC_KOV_URL=$("${SCRIPT_DIR}/deploy-monitoring.sh" || true)

log_step "Deploying monitoring on highload cluster"
kubectl config use-context "$(kubectl config get-contexts -o name | grep "${HIGHLOAD_CLUSTER}" | head -1)"
HIGHLOAD_KOV_URL=$("${SCRIPT_DIR}/deploy-monitoring.sh" || true)

# Step 8: Setup contexts
"${SCRIPT_DIR}/setup-contexts.sh" "${BASIC_CLUSTER}" "${HIGHLOAD_CLUSTER}"

# Summary
log_step "Setup Complete!"
echo ""
echo "========================================="
echo "  Karpenter Demo Environment Ready"
echo "========================================="
echo ""
echo "  Karpenter version: ${KARPENTER_VERSION}"
echo "  K8s version:       ${K8S_VERSION}"
echo "  Region:            ${AWS_DEFAULT_REGION}"
echo ""
echo "  Basic cluster:     ${BASIC_CLUSTER}"
echo "  Highload cluster:  ${HIGHLOAD_CLUSTER}"
echo ""
echo "  Contexts:"
echo "    kubectl config use-context kd-basic"
echo "    kubectl config use-context kd-hl"
echo ""
if [[ -n "${BASIC_KOV_URL:-}" ]]; then
  echo "  kube-ops-view (basic):    http://${BASIC_KOV_URL}"
fi
if [[ -n "${HIGHLOAD_KOV_URL:-}" ]]; then
  echo "  kube-ops-view (highload): http://${HIGHLOAD_KOV_URL}"
fi
echo ""
echo "  Useful commands:"
echo "    watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'"
echo "    kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller"
echo ""
echo "  Run high-load test:"
echo "    kubectl config use-context kd-hl"
echo "    cd high-load && ./create-workload.sh 3000 500"
echo ""
echo "  Teardown:"
echo "    ./scripts/teardown.sh ${BASIC_CLUSTER} ${HIGHLOAD_CLUSTER}"
echo "========================================="
```

**Step 2: Make executable and validate**

Run: `chmod +x scripts/setup-all.sh && bash -n scripts/setup-all.sh && echo "OK"`
Expected: `OK`

**Step 3: Commit**

```bash
git add scripts/setup-all.sh
git commit -m "feat: add master setup-all.sh script"
```

---

### Task 15: Create .claude/commands/setup-demo.md

**Files:**
- Create: `.claude/commands/setup-demo.md`

**Step 1: Write setup-demo.md**

```markdown
---
description: Set up Karpenter demo environment with two EKS clusters
---

You are setting up a Karpenter demo environment. Follow these steps exactly:

## Step 1: Check prerequisites

Run `./scripts/check-prereqs.sh` to verify all tools are installed (kubectl, eksctl, helm, aws-cli) and AWS credentials are configured.

## Step 2: Get latest Karpenter version

Use WebFetch to check https://karpenter.sh/docs/getting-started/ for the latest Karpenter version. Also run `./scripts/get-latest-karpenter.sh` as a backup.

Ask the user: "Latest Karpenter version is X.Y.Z. Use this version?"

## Step 3: Generate cluster names

Generate cluster names using today's date:
- Basic: `kd-basic-YY-MM-DD` (e.g., kd-basic-26-03-02)
- Highload: `kd-hl-YY-MM-DD` (e.g., kd-hl-26-03-02)

Show the names to the user and confirm.

## Step 4: Create clusters

Run for each cluster:
```bash
export KARPENTER_VERSION="<version>"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
./scripts/create-cluster.sh basic <basic-cluster-name>
./scripts/create-cluster.sh highload <highload-cluster-name>
```

This takes ~15-20 minutes per cluster. Keep the user informed of progress.

## Step 5: Install Karpenter

For each cluster, switch context and install:

```bash
# Basic cluster
kubectl config use-context <context-with-basic-cluster-name>
./scripts/install-karpenter.sh basic <basic-cluster-name> <karpenter-version>

# Highload cluster
kubectl config use-context <context-with-highload-cluster-name>
./scripts/install-karpenter.sh highload <highload-cluster-name> <karpenter-version>
```

## Step 6: Deploy monitoring

For each cluster:
```bash
kubectl config use-context <context>
./scripts/deploy-monitoring.sh
```

## Step 7: Setup contexts

```bash
./scripts/setup-contexts.sh <basic-cluster-name> <highload-cluster-name>
```

## Step 8: Show summary

Show the user:
- Both cluster names
- How to switch between them (`kubectl config use-context kd-basic` / `kd-hl`)
- kube-ops-view URLs for both clusters
- How to run the basic demo (apply inflate-10pods.yaml, scale to 60)
- How to run the split demo (delete default NodePool, apply spot+on-demand NodePools, apply 600-pod split)
- How to run highload test (`cd high-load && ./create-workload.sh 3000 500`)
- How to tear down (`./scripts/teardown.sh <basic-name> <highload-name>`)
- Separate kubeconfig per terminal option
```

**Step 2: Commit**

```bash
git add .claude/commands/setup-demo.md
git commit -m "feat: add /setup-demo Claude Code command"
```

---

### Task 16: Create .claude/commands/teardown-demo.md

**Files:**
- Create: `.claude/commands/teardown-demo.md`

**Step 1: Write teardown-demo.md**

```markdown
---
description: Tear down Karpenter demo clusters
---

You are tearing down the Karpenter demo environment.

## Step 1: List existing clusters

Run `aws eks list-clusters --region eu-north-1 --output text` to find demo clusters.
Look for clusters matching pattern `kd-basic-*` and `kd-hl-*`.

Show the user which clusters were found and confirm deletion.

## Step 2: Run teardown

```bash
./scripts/teardown.sh <cluster-name-1> <cluster-name-2>
```

## Step 3: Verify

Run `aws eks list-clusters --region eu-north-1 --output text` again to confirm clusters are deleted.

Also check for leftover CloudFormation stacks:
```bash
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --region eu-north-1 --query 'StackSummaries[?starts_with(StackName, `Karpenter-kd-`)].StackName' --output text
```

Report results to the user.
```

**Step 2: Commit**

```bash
git add .claude/commands/teardown-demo.md
git commit -m "feat: add /teardown-demo Claude Code command"
```

---

### Task 17: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Rewrite CLAUDE.md to reflect new structure**

The new CLAUDE.md should document:
- New repository structure (scripts/, manifests/, high-load/, .claude/commands/)
- How to use `/setup-demo` and `/teardown-demo` commands
- How to use `./scripts/setup-all.sh` standalone
- Essential commands (same useful monitoring commands)
- Architecture of the two-cluster setup
- Demo flow for basic (inflate -> scale -> consolidation -> split)
- Demo flow for highload (batch workloads)
- Environment variables (from config.env, not manual export)

Remove all references to old directories (karpenter-demo01/, cluster-autoscaler/, vscode-instances/, cloud9-config.md).

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for new repo structure"
```

---

### Task 18: Create README.md

**Files:**
- Modify: `README.md`

**Step 1: Rewrite README.md**

The new README should cover:
- What this repo does (Karpenter demo with two clusters)
- Prerequisites (tools needed)
- Quick start with Claude Code (`/setup-demo`)
- Quick start without Claude (`./scripts/setup-all.sh`)
- Demo 1: Basic Karpenter (10 pods -> 60 pods -> consolidation)
- Demo 2: Split spot/on-demand (delete default NodePool, apply split, 600 pods)
- Demo 3: High-load (3000 pods in batches)
- Monitoring (kube-ops-view URLs)
- Context switching between clusters
- Teardown instructions
- Directory structure reference

**Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README.md for automated demo setup"
```

---

### Task 19: Final verification and cleanup

**Step 1: Verify all scripts are executable**

Run: `find scripts/ high-load/ -name '*.sh' -exec chmod +x {} \;`

**Step 2: Verify all bash scripts pass syntax check**

Run: `for f in scripts/*.sh high-load/*.sh; do echo "Checking $f..."; bash -n "$f" && echo "OK" || echo "FAIL"; done`
Expected: all OK

**Step 3: Verify directory structure matches design**

Run: `find . -not -path './.git/*' -not -path './.git' -not -name '.DS_Store' | sort`
Expected: matches the design doc structure

**Step 4: Verify no hardcoded cluster names in manifests**

Run: `grep -r "karpenter-demo-" manifests/ || echo "No hardcoded cluster names found"`
Expected: "No hardcoded cluster names found"

**Step 5: Final commit**

```bash
git add -A
git status
# If there are uncommitted changes:
git commit -m "chore: final cleanup and verification"
```
