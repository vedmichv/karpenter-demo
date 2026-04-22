#!/bin/bash
#
# CloudShell-compatible replacement for 00-setup.sh
# Original script uses EC2 IMDS (169.254.169.254) which is not available in CloudShell.
# This version uses AWS CLI and environment variables instead.
#
# Usage:
#   export AWS_REGION=us-east-1   # <-- set your workshop region first!
#   bash cloudshell-00-setup.sh
#

set -eo pipefail

# ── Validate region ──────────────────────────────────────────────────────────
if [ -z "${AWS_REGION:-}" ]; then
    echo "ERROR: AWS_REGION is not set."
    echo "Run: export AWS_REGION=<your-workshop-region>"
    echo "Hint: check your CloudShell URL for the region, e.g. https://us-east-1.console.aws.amazon.com/cloudshell/"
    exit 1
fi

echo "==> Using AWS_REGION=$AWS_REGION"

# ── Install dependencies ─────────────────────────────────────────────────────
echo "==> Installing dependencies (jq, gettext, bash-completion)..."
sudo yum -y -q install jq gettext bash-completion 2>/dev/null || true

# ── AWS CLI: CloudShell already has v2, just configure region ─────────────────
aws configure set default.region ${AWS_REGION}

# ── Account and AZ info (using CLI, not IMDS) ─────────────────────────────────
export ACCOUNT_ID=$(aws sts get-caller-identity --region $AWS_REGION --output text --query Account)
export AZS=($(aws ec2 describe-availability-zones --region $AWS_REGION --query 'AvailabilityZones[].ZoneName' --output text))

echo "==> ACCOUNT_ID=$ACCOUNT_ID"
echo "==> AZS=${AZS[*]}"

# ── Persist to bash_profile (idempotent: update if exists, append if not) ─────
update_bash_profile() {
    local var_name=$1
    local var_value=$2
    if grep -q "export ${var_name}=" ~/.bash_profile 2>/dev/null; then
        sed -i "s|export ${var_name}=.*|export ${var_name}=${var_value}|" ~/.bash_profile
    else
        echo "export ${var_name}=${var_value}" >> ~/.bash_profile
    fi
}

update_bash_profile "ACCOUNT_ID" "$ACCOUNT_ID"
update_bash_profile "AWS_REGION" "$AWS_REGION"
update_bash_profile "AZS" "(${AZS[*]})"

# ── Network: VPC and subnets (from CloudFormation stack tags) ─────────────────
echo "==> Looking up VPC and subnets..."
export MyVPC=$(aws ec2 describe-vpcs --region $AWS_REGION \
    --query 'Vpcs[*].[VpcId]' \
    --filters "Name=tag-key,Values=IsUsedForDeploy" --output text)

export PrivateSubnet1=$(aws ec2 describe-subnets --region $AWS_REGION \
    --query 'Subnets[*].[SubnetId]' \
    --filters "Name=tag-value,Values=VPC-Observability Private Subnet (AZ1)" --output text)
export PrivateSubnet2=$(aws ec2 describe-subnets --region $AWS_REGION \
    --query 'Subnets[*].[SubnetId]' \
    --filters "Name=tag-value,Values=VPC-Observability Private Subnet (AZ2)" --output text)
export PrivateSubnet3=$(aws ec2 describe-subnets --region $AWS_REGION \
    --query 'Subnets[*].[SubnetId]' \
    --filters "Name=tag-value,Values=VPC-Observability Private Subnet (AZ3)" --output text)

export PublicSubnet1=$(aws ec2 describe-subnets --region $AWS_REGION \
    --query 'Subnets[*].[SubnetId]' \
    --filters "Name=tag-value,Values=VPC-Observability Public Subnet (AZ1)" --output text)
export PublicSubnet2=$(aws ec2 describe-subnets --region $AWS_REGION \
    --query 'Subnets[*].[SubnetId]' \
    --filters "Name=tag-value,Values=VPC-Observability Public Subnet (AZ2)" --output text)
export PublicSubnet3=$(aws ec2 describe-subnets --region $AWS_REGION \
    --query 'Subnets[*].[SubnetId]' \
    --filters "Name=tag-value,Values=VPC-Observability Public Subnet (AZ3)" --output text)

# Persist network vars
for var in MyVPC PrivateSubnet1 PrivateSubnet2 PrivateSubnet3 PublicSubnet1 PublicSubnet2 PublicSubnet3; do
    update_bash_profile "$var" "${!var}"
done

# ── Validate network ─────────────────────────────────────────────────────────
if [ -z "$MyVPC" ]; then
    echo ""
    echo "WARNING: VPC not found! The workshop CloudFormation stack may not be deployed."
    echo "Check: aws cloudformation list-stacks --region $AWS_REGION \\"
    echo "         --query 'StackSummaries[?StackStatus==\`CREATE_COMPLETE\`].StackName'"
    echo ""
fi

echo "==> VPC=$MyVPC"
echo "==> PrivateSubnets=$PrivateSubnet1 $PrivateSubnet2 $PrivateSubnet3"
echo "==> PublicSubnets=$PublicSubnet1 $PublicSubnet2 $PublicSubnet3"

# ── EKS kubeconfig ───────────────────────────────────────────────────────────
echo "==> Configuring EKS kubeconfig..."
CLUSTERS=$(aws eks list-clusters --region $AWS_REGION --output text 2>/dev/null | awk '{print $2}')
if [ -n "$CLUSTERS" ]; then
    echo "$CLUSTERS" | while read -r cluster; do
        echo "    Adding cluster: $cluster"
        aws eks --region $AWS_REGION update-kubeconfig --name "$cluster"
    done
else
    echo "    No EKS clusters found in $AWS_REGION"
fi

# ── Clone lab repository (skip if already cloned) ────────────────────────────
cd ~
if [ ! -d "observability-with-amazon-opensearch" ]; then
    echo "==> Cloning lab repository..."
    git clone https://github.com/aws-samples/observability-with-amazon-opensearch
else
    echo "==> Lab repository already cloned, skipping."
fi

# ── Reload profile (disable strict mode temporarily — AL2023 /etc/bashrc uses unbound vars) ──
set +e
source ~/.bash_profile 2>/dev/null || true
set -e

# ── Final verification ───────────────────────────────────────────────────────
echo ""
echo "============================================"
echo "  Setup complete! Verification:"
echo "============================================"
echo "  ACCOUNT_ID : $ACCOUNT_ID"
echo "  AWS_REGION  : $AWS_REGION"
echo "  VPC         : $MyVPC"
echo "  EKS cluster : $(aws eks list-clusters --region $AWS_REGION --output text 2>/dev/null | awk '{print $2}' || echo 'none')"
echo ""
echo "  kubectl test:"
kubectl get nodes 2>/dev/null && echo "  ✓ kubectl works" || echo "  ✗ kubectl cannot reach nodes (may need VPC access or permissions)"
echo ""
echo "Next step: cd ~/observability-with-amazon-opensearch/scripts && bash cloudshell-01-build-push.sh"
echo "============================================"
