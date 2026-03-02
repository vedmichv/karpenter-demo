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
