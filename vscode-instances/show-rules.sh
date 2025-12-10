#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="${STACK_NAME:-karpenter-demo-vscode}"
AWS_REGION=$(aws configure get region)

if [ -z "$AWS_REGION" ]; then
    read -p "Enter AWS Region: " AWS_REGION
fi

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Security Group Rules${NC}"
echo -e "${GREEN}======================================${NC}"
echo

# Get security group ID
SG_ID=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --region $AWS_REGION \
  --query 'StackResources[?LogicalResourceId==`VSCodeSecurityGroup`].PhysicalResourceId' \
  --output text)

if [ -z "$SG_ID" ]; then
    echo -e "${YELLOW}Error: Could not find security group for stack $STACK_NAME${NC}"
    exit 1
fi

echo -e "${GREEN}Security Group ID:${NC} $SG_ID"
echo -e "${GREEN}Stack:${NC} $STACK_NAME"
echo -e "${GREEN}Region:${NC} $AWS_REGION"
echo

# Show inbound rules
echo -e "${GREEN}Inbound Rules:${NC}"
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --region $AWS_REGION \
  --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[*].[CidrIp,Description]]' \
  --output table

# Check if no rules
RULE_COUNT=$(aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --region $AWS_REGION \
  --query 'length(SecurityGroups[0].IpPermissions)' \
  --output text)

if [ "$RULE_COUNT" == "0" ]; then
    echo
    echo -e "${YELLOW}⚠️  No inbound rules configured!${NC}"
    echo -e "${YELLOW}Instances are not accessible from the internet.${NC}"
    echo
    echo "To open ports for your IP, run: ./open-ports.sh"
fi

echo
echo -e "${GREEN}Outbound Rules:${NC}"
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --region $AWS_REGION \
  --query 'SecurityGroups[0].IpPermissionsEgress[*].[IpProtocol,FromPort,ToPort,IpRanges[*].CidrIp]' \
  --output table

# Show your current IP
echo
echo -e "${GREEN}Your Current Public IP:${NC} $(curl -s https://checkip.amazonaws.com)"
