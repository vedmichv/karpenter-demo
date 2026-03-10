---
description: Tear down Karpenter demo clusters
---

You are tearing down the Karpenter demo environment.

## Step 1: List existing clusters

Run `aws eks list-clusters --region eu-north-1 --output text` to find demo clusters.
Look for clusters matching pattern `k-basic-*` and `k-hl-*`.

Show the user which clusters were found and confirm deletion.

## Step 2: Run teardown

```bash
./scripts/teardown.sh <cluster-name-1> <cluster-name-2>
```

## Step 3: Verify

Run `aws eks list-clusters --region eu-north-1 --output text` again to confirm clusters are deleted.

Also check for leftover CloudFormation stacks:
```bash
aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE --region eu-north-1 --query 'StackSummaries[?starts_with(StackName, `Karpenter-k-`)].StackName' --output text
```

Report results to the user.
