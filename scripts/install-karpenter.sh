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
