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

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Open Ports for VSCode Access${NC}"
echo -e "${GREEN}======================================${NC}"
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

# Get current public IP
echo "Detecting your public IP..."
MY_IP=$(curl -s https://checkip.amazonaws.com)

if [ -z "$MY_IP" ]; then
    echo -e "${YELLOW}Could not auto-detect IP. Please enter manually:${NC}"
    read -p "Your public IP address: " MY_IP
fi

echo -e "${GREEN}Your IP Address:${NC} $MY_IP"
echo

# Confirm
echo -e "${YELLOW}This will add the following rules to security group $SG_ID:${NC}"
echo "  - Port 8080 (VSCode web) from $MY_IP/32"
echo "  - Port 22 (SSH) from $MY_IP/32"
echo

read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Cancelled"
    exit 0
fi

# Add port 8080 rule
echo
echo "Opening port 8080 for VSCode..."
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr ${MY_IP}/32 \
  --region $AWS_REGION \
  --description "VSCode web access from ${MY_IP} added $(date +%Y-%m-%d)" \
  2>&1 || echo -e "${YELLOW}Port 8080 rule may already exist${NC}"

# Add port 22 rule
echo "Opening port 22 for SSH..."
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr ${MY_IP}/32 \
  --region $AWS_REGION \
  --description "SSH access from ${MY_IP} added $(date +%Y-%m-%d)" \
  2>&1 || echo -e "${YELLOW}Port 22 rule may already exist${NC}"

echo
echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}Ports opened successfully!${NC}"
echo -e "${GREEN}======================================${NC}"
echo
echo -e "${GREEN}You can now access VSCode at:${NC}"

# Get instance IPs
INSTANCE_IPS=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $AWS_REGION \
  --query 'Stacks[0].Outputs[?contains(OutputKey,`PublicIP`)].OutputValue' \
  --output text)

for IP in $INSTANCE_IPS; do
    echo "  http://$IP:8080"
done

echo
echo -e "${YELLOW}Note: Wait 2-3 minutes after stack creation for instances to complete setup${NC}"
