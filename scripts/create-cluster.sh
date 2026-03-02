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
