#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}======================================${NC}"
echo -e "${GREEN}VSCode Instances Deployment Script${NC}"
echo -e "${GREEN}======================================${NC}"
echo

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI is not installed${NC}"
    exit 1
fi

# Get AWS account and region
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)

if [ -z "$AWS_REGION" ]; then
    echo -e "${YELLOW}No default region found. Please set AWS_REGION:${NC}"
    read -p "Enter AWS Region (e.g., us-east-1): " AWS_REGION
    export AWS_REGION
fi

echo -e "${GREEN}AWS Account ID:${NC} $AWS_ACCOUNT_ID"
echo -e "${GREEN}AWS Region:${NC} $AWS_REGION"
echo

# Stack name
STACK_NAME="${STACK_NAME:-karpenter-demo-vscode}"
echo -e "${GREEN}Stack Name:${NC} $STACK_NAME"

# Get parameters
read -p "Enter EC2 Key Pair name: " KEY_PAIR_NAME

if [ -z "$KEY_PAIR_NAME" ]; then
    echo -e "${RED}Error: Key Pair name is required${NC}"
    exit 1
fi

# Check if key pair exists
if ! aws ec2 describe-key-pairs --key-names "$KEY_PAIR_NAME" --region "$AWS_REGION" &> /dev/null; then
    echo -e "${RED}Error: Key Pair '$KEY_PAIR_NAME' not found in region $AWS_REGION${NC}"
    echo "Available key pairs:"
    aws ec2 describe-key-pairs --region "$AWS_REGION" --query 'KeyPairs[].KeyName' --output table
    exit 1
fi

read -sp "Enter VSCode Password (min 8 characters): " VSCODE_PASSWORD
echo
read -sp "Confirm VSCode Password: " VSCODE_PASSWORD_CONFIRM
echo

if [ "$VSCODE_PASSWORD" != "$VSCODE_PASSWORD_CONFIRM" ]; then
    echo -e "${RED}Error: Passwords do not match${NC}"
    exit 1
fi

if [ ${#VSCODE_PASSWORD} -lt 8 ]; then
    echo -e "${RED}Error: Password must be at least 8 characters${NC}"
    exit 1
fi

echo
read -p "Enter Instance Type (default: t3.xlarge): " INSTANCE_TYPE
INSTANCE_TYPE=${INSTANCE_TYPE:-t3.xlarge}

read -p "Enter EBS Volume Size in GB (default: 50): " VOLUME_SIZE
VOLUME_SIZE=${VOLUME_SIZE:-50}

echo
echo -e "${YELLOW}Summary:${NC}"
echo "  Stack Name: $STACK_NAME"
echo "  Region: $AWS_REGION"
echo "  Key Pair: $KEY_PAIR_NAME"
echo "  Instance Type: $INSTANCE_TYPE"
echo "  Volume Size: ${VOLUME_SIZE}GB"
echo
echo -e "${RED}SECURITY NOTE:${NC}"
echo "  The security group will BLOCK ALL INBOUND TRAFFIC by default."
echo "  After deployment, you MUST manually open ports (8080, 22) to access the instances."
echo "  See SECURITY-GROUP-MANAGEMENT.md for instructions."
echo

read -p "Deploy stack with these parameters? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Deployment cancelled"
    exit 0
fi

echo
echo -e "${GREEN}Deploying CloudFormation stack...${NC}"

aws cloudformation create-stack \
  --stack-name "$STACK_NAME" \
  --template-body file://cloudformation.yaml \
  --parameters \
    ParameterKey=KeyPairName,ParameterValue="$KEY_PAIR_NAME" \
    ParameterKey=VSCodePassword,ParameterValue="$VSCODE_PASSWORD" \
    ParameterKey=InstanceType,ParameterValue="$INSTANCE_TYPE" \
    ParameterKey=VolumeSize,ParameterValue="$VOLUME_SIZE" \
  --capabilities CAPABILITY_NAMED_IAM \
  --region "$AWS_REGION"

echo
echo -e "${GREEN}Stack creation initiated!${NC}"
echo -e "${YELLOW}Waiting for stack to complete (this takes 5-10 minutes)...${NC}"
echo

aws cloudformation wait stack-create-complete \
  --stack-name "$STACK_NAME" \
  --region "$AWS_REGION"

if [ $? -eq 0 ]; then
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}Stack deployed successfully!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo

    # Get outputs
    echo -e "${GREEN}Access Information:${NC}"
    echo
    aws cloudformation describe-stacks \
      --stack-name "$STACK_NAME" \
      --region "$AWS_REGION" \
      --query 'Stacks[0].Outputs[?OutputKey==`VSCode1URL` || OutputKey==`VSCode2URL` || OutputKey==`VSCode1SSH` || OutputKey==`VSCode2SSH`].[OutputKey,OutputValue]' \
      --output table

    echo
    echo -e "${YELLOW}Note: It may take 2-3 minutes after stack creation for instances to complete setup${NC}"
    echo -e "${YELLOW}Your VSCode password: (saved securely)${NC}"
    echo
else
    echo -e "${RED}Stack creation failed!${NC}"
    echo "Check CloudFormation console for details:"
    echo "https://console.aws.amazon.com/cloudformation"
    exit 1
fi
