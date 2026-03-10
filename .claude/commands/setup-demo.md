---
description: Set up Karpenter demo environment with two EKS clusters
---

You are setting up a Karpenter demo environment. Follow these steps exactly:

## Step 1: Check prerequisites

Run `./scripts/check-prereqs.sh` to verify all tools are installed (kubectl, eksctl, helm, aws-cli) and AWS credentials are configured.

## Step 2: Get latest Karpenter version

Use WebFetch to check https://karpenter.sh/docs/getting-started/ for the latest Karpenter version. Also run `./scripts/get-latest-karpenter.sh` as a backup.

Ask the user: "Latest Karpenter version is X.Y.Z. Use this version?"

## Step 3: Generate cluster names

Generate cluster names using today's date:
- Basic: `k-basic-YY-MM-DD` (e.g., k-basic-26-03-02)
- Highload: `k-hl-YY-MM-DD` (e.g., k-hl-26-03-02)

Show the names to the user and confirm.

## Step 4: Create clusters

Run for each cluster:
```bash
export KARPENTER_VERSION="<version>"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
./scripts/create-cluster.sh basic <basic-cluster-name>
./scripts/create-cluster.sh highload <highload-cluster-name>
```

This takes ~15-20 minutes per cluster. Keep the user informed of progress.

## Step 5: Install Karpenter

For each cluster, switch context and install:

```bash
# Basic cluster
kubectl config use-context <context-with-basic-cluster-name>
./scripts/install-karpenter.sh basic <basic-cluster-name> <karpenter-version>

# Highload cluster
kubectl config use-context <context-with-highload-cluster-name>
./scripts/install-karpenter.sh highload <highload-cluster-name> <karpenter-version>
```

## Step 6: Deploy monitoring

For each cluster:
```bash
kubectl config use-context <context>
./scripts/deploy-monitoring.sh
```

## Step 7: Setup contexts

```bash
./scripts/setup-contexts.sh <basic-cluster-name> <highload-cluster-name>
```

## Step 8: Show summary

Show the user:
- Both cluster names
- How to switch between them (`kubectl config use-context k-basic` / `k-hl`)
- kube-ops-view URLs for both clusters
- How to run the basic demo (apply inflate-10pods.yaml, scale to 60)
- How to run the split demo (delete default NodePool, apply spot+on-demand NodePools, apply 600-pod split)
- How to run highload test (`cd high-load && ./create-workload.sh 3000 500`)
- How to tear down (`./scripts/teardown.sh <basic-name> <highload-name>`)
- Separate kubeconfig per terminal option
