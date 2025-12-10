#!/bin/bash
set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

STACK_NAME="${STACK_NAME:-karpenter-demo-vscode}"
AWS_REGION=$(aws configure get region)

if [ -z "$AWS_REGION" ]; then
    read -p "Enter AWS Region: " AWS_REGION
fi

echo -e "${YELLOW}This will delete the stack: $STACK_NAME in region $AWS_REGION${NC}"
echo -e "${RED}All EC2 instances and data will be permanently deleted!${NC}"
echo

read -p "Are you sure? Type 'delete' to confirm: " CONFIRM

if [ "$CONFIRM" != "delete" ]; then
    echo "Deletion cancelled"
    exit 0
fi

echo -e "${GREEN}Deleting stack...${NC}"

aws cloudformation delete-stack \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION"

echo -e "${YELLOW}Waiting for stack deletion...${NC}"

aws cloudformation wait stack-delete-complete \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION"

echo -e "${GREEN}Stack deleted successfully!${NC}"
