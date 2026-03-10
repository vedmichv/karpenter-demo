#!/usr/bin/env bash
# setup-contexts.sh - Rename kubectl contexts to short aliases
# Usage: ./setup-contexts.sh <basic-cluster-name> <highload-cluster-name>
source "$(dirname "$0")/lib.sh"
load_config

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
log_info "Renaming '${BASIC_CONTEXT}' -> 'k-basic'"
kubectl config rename-context "${BASIC_CONTEXT}" k-basic

log_info "Renaming '${HIGHLOAD_CONTEXT}' -> 'k-hl'"
kubectl config rename-context "${HIGHLOAD_CONTEXT}" k-hl

log_ok "Contexts configured:"
echo ""
echo "  Switch to basic cluster:    kubectl config use-context k-basic"
echo "  Switch to highload cluster: kubectl config use-context k-hl"
echo ""
echo "  Or use separate kubeconfigs per terminal:"
echo "    aws eks update-kubeconfig --name ${BASIC_CLUSTER} --region ${AWS_DEFAULT_REGION:-eu-north-1} --kubeconfig ~/.kube/config-basic"
echo "    aws eks update-kubeconfig --name ${HIGHLOAD_CLUSTER} --region ${AWS_DEFAULT_REGION:-eu-north-1} --kubeconfig ~/.kube/config-highload"
echo ""
echo "  Then in each terminal:"
echo "    export KUBECONFIG=~/.kube/config-basic   # Terminal 1"
echo "    export KUBECONFIG=~/.kube/config-highload # Terminal 2"
