#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

STACK_NAME="${STACK_NAME:-karpenter-demo-vscode}"
AWS_REGION=$(aws configure get region)

if [ -z "$AWS_REGION" ]; then
    read -p "Enter AWS Region: " AWS_REGION
fi

echo -e "${RED}======================================${NC}"
echo -e "${RED}Close All Inbound Ports (Lockdown)${NC}"
echo -e "${RED}======================================${NC}"
echo

# Get security group ID
echo "Finding security group..."
SG_ID=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --region $AWS_REGION \
  --query 'StackResources[?LogicalResourceId==`VSCodeSecurityGroup`].PhysicalResourceId' \
  --output text)

if [ -z "$SG_ID" ]; then
    echo -e "${RED}Error: Could not find security group for stack $STACK_NAME${NC}"
    exit 1
fi

echo -e "${GREEN}Security Group ID:${NC} $SG_ID"
echo

# Show current rules
echo -e "${YELLOW}Current inbound rules:${NC}"
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --region $AWS_REGION \
  --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[*].CidrIp]' \
  --output table

echo
echo -e "${RED}WARNING: This will remove ALL inbound rules!${NC}"
echo -e "${RED}You will NOT be able to access the instances until you add rules again.${NC}"
echo

read -p "Are you sure? Type 'close' to confirm: " CONFIRM

if [ "$CONFIRM" != "close" ]; then
    echo "Cancelled"
    exit 0
fi

# Get all rules
RULES=$(aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --region $AWS_REGION \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json)

# Check if there are any rules to remove
if [ "$RULES" == "[]" ]; then
    echo -e "${YELLOW}No inbound rules to remove${NC}"
    exit 0
fi

# Revoke all rules
echo "Removing all inbound rules..."
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --region $AWS_REGION \
  --ip-permissions "$RULES"

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}All inbound ports closed${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo -e "${YELLOW}To re-enable access, run: ./open-ports.sh${NC}"
