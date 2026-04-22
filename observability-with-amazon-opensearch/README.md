# Microservice Observability with Amazon OpenSearch Service — CloudShell Scripts

Drop-in replacement scripts for the [Microservice Observability with Amazon OpenSearch Service](https://catalog.workshops.aws/microservice-observability/en-US) workshop that work in **AWS CloudShell**.

## Why?

The original workshop scripts (`00-setup.sh`, `01-build-push.sh`) use EC2 Instance Metadata Service (IMDS) to detect the AWS region and account ID. This only works on EC2-based environments (Cloud9, EC2 instances). **CloudShell is a container** — IMDS is not available, causing all scripts to fail silently with cascading errors like:

```
aws: [ERROR]: Invalid endpoint: https://ec2..amazonaws.com
```

## What's Changed

| Original | Replacement | Changes |
|----------|-------------|---------|
| `00-setup.sh` | `00-setup.sh` | Uses AWS CLI instead of IMDS; adds validation and verification output |
| `01-build-push.sh` | `01-build-push.sh` | Removes IMDS and Docker login; adds `--region` to all CLI calls; improved build status checking |

## Quick Start

### Option A: Run directly from GitHub (recommended)

```bash
# Set your workshop region
export AWS_REGION=us-east-1

# Step 1: Setup
curl -sSL https://raw.githubusercontent.com/vedmich/karpenter-demo/main/observability-with-amazon-opensearch/00-setup.sh | bash

# Step 2: Build and push
cd ~/observability-with-amazon-opensearch/scripts
curl -sSL https://raw.githubusercontent.com/vedmich/karpenter-demo/main/observability-with-amazon-opensearch/01-build-push.sh | bash
```

### Option B: Download and run

```bash
export AWS_REGION=us-east-1

# Download scripts
curl -sSLO https://raw.githubusercontent.com/vedmich/karpenter-demo/main/observability-with-amazon-opensearch/00-setup.sh
curl -sSLO https://raw.githubusercontent.com/vedmich/karpenter-demo/main/observability-with-amazon-opensearch/01-build-push.sh
chmod +x 00-setup.sh 01-build-push.sh

# Step 1: Setup
bash 00-setup.sh

# Step 2: Build (run from the workshop scripts/ directory)
cp 01-build-push.sh ~/observability-with-amazon-opensearch/scripts/
cd ~/observability-with-amazon-opensearch/scripts
bash 01-build-push.sh
```

## Prerequisites

- Workshop CloudFormation stack must be deployed in your region (creates VPC, EKS cluster, OSIS pipelines, CodeBuild projects)
- `AWS_REGION` must be set before running scripts

## Verification

After running `00-setup.sh`, you should see:

```
============================================
  Setup complete! Verification:
============================================
  ACCOUNT_ID : 123456789012
  AWS_REGION  : us-east-1
  VPC         : vpc-0xxxxxxxxxxxx
  EKS cluster : observability-cluster
============================================
```

If `VPC` is empty, check that the CloudFormation stack is deployed:

```bash
aws cloudformation list-stacks --region $AWS_REGION \
  --query 'StackSummaries[?StackStatus==`CREATE_COMPLETE`].StackName' --output text
```

## Environment Comparison

| Feature | Cloud9 | CloudShell | EC2 |
|---------|--------|------------|-----|
| IMDS (169.254.169.254) | Yes | **No** | Yes |
| Docker | Yes | **No** | Yes |
| Persistent storage | EBS | ~/  (1 GB) | EBS |
| AWS CLI v2 | Pre-installed | Pre-installed | Install needed |
| kubectl | Install needed | Install needed | Install needed |
