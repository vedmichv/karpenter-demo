#!/usr/bin/env bash
# teardown.sh - Delete one or both demo clusters
# Usage: ./teardown.sh <cluster-name> [cluster-name-2]
source "$(dirname "$0")/lib.sh"
load_config

if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <cluster-name> [cluster-name-2]"
  echo ""
  echo "Example: $0 k-basic-26-03-02 k-hl-26-03-02"
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
  kubectl config delete-context "k-basic" 2>/dev/null || true
  kubectl config delete-context "k-hl" 2>/dev/null || true

  log_ok "Cluster ${cluster_name} deleted"
}

for cluster in "$@"; do
  delete_cluster "$cluster"
done

log_ok "Teardown complete"
