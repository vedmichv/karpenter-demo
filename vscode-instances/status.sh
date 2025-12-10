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

echo -e "${GREEN}Stack Status for: $STACK_NAME${NC}"
echo

# Get stack status
STATUS=$(aws cloudformation describe-stacks \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION" \
  --query 'Stacks[0].StackStatus' \
  --output text 2>/dev/null || echo "NOT_FOUND")

if [ "$STATUS" == "NOT_FOUND" ]; then
    echo -e "${YELLOW}Stack not found${NC}"
    exit 1
fi

echo "Status: $STATUS"
echo

# Get outputs
if [ "$STATUS" == "CREATE_COMPLETE" ] || [ "$STATUS" == "UPDATE_COMPLETE" ]; then
    echo -e "${GREEN}Outputs:${NC}"
    aws cloudformation describe-stacks \
      --stack-name "$STACK_NAME" \
      --region "$AWS_REGION" \
      --query 'Stacks[0].Outputs' \
      --output table

    echo
    echo -e "${GREEN}Instance Details:${NC}"
    INSTANCE_IDS=$(aws cloudformation describe-stack-resources \
      --stack-name "$STACK_NAME" \
      --region "$AWS_REGION" \
      --query 'StackResources[?ResourceType==`AWS::EC2::Instance`].PhysicalResourceId' \
      --output text)

    if [ -n "$INSTANCE_IDS" ]; then
        aws ec2 describe-instances \
          --instance-ids $INSTANCE_IDS \
          --region "$AWS_REGION" \
          --query 'Reservations[].Instances[].[InstanceId,State.Name,InstanceType,PublicIpAddress,Tags[?Key==`Name`].Value|[0]]' \
          --output table
    fi
else
    echo -e "${YELLOW}Stack is in $STATUS state${NC}"

    # Show events for troubleshooting
    echo
    echo "Recent events:"
    aws cloudformation describe-stack-events \
      --stack-name "$STACK_NAME" \
      --region "$AWS_REGION" \
      --max-items 10 \
      --query 'StackEvents[].[Timestamp,ResourceStatus,ResourceType,LogicalResourceId,ResourceStatusReason]' \
      --output table
fi
