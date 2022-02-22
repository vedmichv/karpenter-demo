Define variables:

```bash
export CLUSTER_NAME="vedmich-karpenter-demo"
export AWS_DEFAULT_REGION="eu-west-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
```
