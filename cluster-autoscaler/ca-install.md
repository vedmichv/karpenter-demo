Define variables:

```bash
export CLUSTER_NAME="vedmich-ca-0825-01"
export AWS_DEFAULT_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
```

Initiate EKS cluster with CA 

```bash
eksctl create cluster -f - << EOF
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "1.23"
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}
managedNodeGroups:
  - instanceType: c5.2xlarge
    amiFamily: AmazonLinux2
    name: ${CLUSTER_NAME}-ng
    desiredCapacity: 1
    minSize: 1
    maxSize: 2
iam:
  withOIDC: true
EOF

export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output text)"
```

## Create nodegroup

```bash
cat >${CLUSTER_NAME}-spot-nodegroup.yaml <<EOF

apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}

managedNodeGroups:
  - name: ${CLUSTER_NAME}-ng-spot-01
    labels: { role: workers }
    instanceTypes: ["c5.large","c5n.large","c6g.large","c5d.large","c5a.large"]
    spot: true
EOF
eksctl create nodegroup --config-file ${CLUSTER_NAME}-spot-nodegroup.yaml
```

