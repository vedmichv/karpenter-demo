#!/bin/bash
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

STACK_NAME="${STACK_NAME:-karpenter-demo-vscode}"
AWS_REGION=$(aws configure get region)
IP_CACHE_FILE=~/.vscode-sg-ip-cache

if [ -z "$AWS_REGION" ]; then
    read -p "Enter AWS Region: " AWS_REGION
fi

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Update My IP Address${NC}"
echo -e "${GREEN}======================================${NC}"
echo

# Get security group ID
SG_ID=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --region $AWS_REGION \
  --query 'StackResources[?LogicalResourceId==`VSCodeSecurityGroup`].PhysicalResourceId' \
  --output text)

if [ -z "$SG_ID" ]; then
    echo -e "${RED}Error: Could not find security group for stack $STACK_NAME${NC}"
    exit 1
fi

# Get current public IP
NEW_IP=$(curl -s https://checkip.amazonaws.com)
echo -e "${GREEN}New IP:${NC} $NEW_IP"

# Check if we have cached IP
if [ -f "$IP_CACHE_FILE" ]; then
    OLD_IP=$(cat $IP_CACHE_FILE)
    echo -e "${YELLOW}Old IP:${NC} $OLD_IP"

    if [ "$OLD_IP" == "$NEW_IP" ]; then
        echo -e "${GREEN}IP address hasn't changed${NC}"
        exit 0
    fi

    echo
    echo "Removing old IP rules..."

    # Remove old port 8080 rule
    aws ec2 revoke-security-group-ingress \
      --group-id $SG_ID \
      --protocol tcp \
      --port 8080 \
      --cidr ${OLD_IP}/32 \
      --region $AWS_REGION \
      2>/dev/null || echo -e "${YELLOW}Old port 8080 rule not found${NC}"

    # Remove old port 22 rule
    aws ec2 revoke-security-group-ingress \
      --group-id $SG_ID \
      --protocol tcp \
      --port 22 \
      --cidr ${OLD_IP}/32 \
      --region $AWS_REGION \
      2>/dev/null || echo -e "${YELLOW}Old port 22 rule not found${NC}"
else
    echo -e "${YELLOW}No cached IP found (first run)${NC}"
fi

echo
echo "Adding new IP rules..."

# Add new port 8080 rule
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr ${NEW_IP}/32 \
  --region $AWS_REGION \
  --description "VSCode access from ${NEW_IP} updated $(date +%Y-%m-%d)"

# Add new port 22 rule
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr ${NEW_IP}/32 \
  --region $AWS_REGION \
  --description "SSH access from ${NEW_IP} updated $(date +%Y-%m-%d)"

# Save new IP
echo $NEW_IP > $IP_CACHE_FILE

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}IP address updated successfully!${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo -e "${GREEN}Access now allowed from:${NC} $NEW_IP"
