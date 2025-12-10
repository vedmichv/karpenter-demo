#!/bin/bash
set -e

# Get AWS Account ID from environment variable or fetch from AWS CLI
if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
  echo "AWS_ACCOUNT_ID not set, fetching from AWS CLI..."
  AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
  if [[ -z "${AWS_ACCOUNT_ID}" ]]; then
    echo "ERROR: Could not determine AWS Account ID. Set AWS_ACCOUNT_ID or configure AWS CLI."
    exit 1
  fi
fi

REGIONS=(ap-south-1 eu-south-1 eu-south-2 me-central-1 ca-central-1 eu-central-1 eu-central-2 us-west-1 us-west-2 eu-north-1 eu-west-3 eu-west-2 eu-west-1 ap-northeast-3 ap-northeast-2 ap-northeast-1 sa-east-1 ap-southeast-1 ap-southeast-2 us-east-1 us-east-2)

echo "=== DISCOVERY PHASE ==="
echo "Account: ${AWS_ACCOUNT_ID}"
echo "Timestamp: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo ""

for region in "${REGIONS[@]}"; do
  echo "--- Region: $region ---"
  
  # EKS Clusters
  aws eks list-clusters --region $region --query 'clusters' --output json 2>/dev/null | jq -r '.[]' | while read cluster; do
    echo "EKS|$region|$cluster"
  done
  
  # EC2 Instances
  aws ec2 describe-instances --region $region --query 'Reservations[].Instances[].[InstanceId,State.Name,Tags]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # ELBv2 (ALB/NLB)
  aws elbv2 describe-load-balancers --region $region --query 'LoadBalancers[].[LoadBalancerArn,LoadBalancerName,Type,Tags]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # Classic ELB
  aws elb describe-load-balancers --region $region --query 'LoadBalancerDescriptions[].[LoadBalancerName,DNSName]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # Auto Scaling Groups
  aws autoscaling describe-auto-scaling-groups --region $region --query 'AutoScalingGroups[].[AutoScalingGroupName,Tags]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # RDS Instances
  aws rds describe-db-instances --region $region --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,TagList]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # RDS Clusters
  aws rds describe-db-clusters --region $region --query 'DBClusters[].[DBClusterIdentifier,Status,TagList]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # VPCs
  aws ec2 describe-vpcs --region $region --query 'Vpcs[].[VpcId,IsDefault,Tags]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # EBS Volumes
  aws ec2 describe-volumes --region $region --query 'Volumes[].[VolumeId,State,Tags]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # Lambda Functions
  aws lambda list-functions --region $region --query 'Functions[].[FunctionName,FunctionArn]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # DynamoDB Tables
  aws dynamodb list-tables --region $region --query 'TableNames' --output json 2>/dev/null | jq -r '.[]'
  
  # ECR Repositories
  aws ecr describe-repositories --region $region --query 'repositories[].[repositoryName,repositoryArn]' --output json 2>/dev/null | jq -r '.[] | @json'
  
  # CloudFormation Stacks
  aws cloudformation list-stacks --region $region --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[].[StackName,StackStatus]' --output json 2>/dev/null | jq -r '.[] | @json'
  
done

# S3 Buckets (global)
echo "--- S3 Buckets (global) ---"
aws s3api list-buckets --query 'Buckets[].[Name,CreationDate]' --output json 2>/dev/null | jq -r '.[] | @json'

echo ""
echo "=== DISCOVERY COMPLETE ==="
