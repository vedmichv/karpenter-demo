Installation process - https://www.eksworkshop.com/beginner/080_scaling/install_kube_ops_view/


Define variables:

```bash
export CLUSTER_NAME="vedmich-karpenter-02"
export AWS_DEFAULT_REGION="eu-west-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
```


```bash
eksctl create cluster -f - << EOF
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "1.21"
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}
managedNodeGroups:
  - instanceType: m5.large
    amiFamily: AmazonLinux2
    name: ${CLUSTER_NAME}-ng
    desiredCapacity: 1
    minSize: 1
    maxSize: 10
iam:
  withOIDC: true
EOF

export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output text)"
```


Get logs from Karpenter:

```bash
kubectl logs -f -n karpenter -l app.kubernetes.io/name=karpenter -c controller
```

Run stress test:

```bash
./create.workload.sh 5000 500
```

Edit values 

https://github.com/aws/karpenter/blob/main/charts/karpenter/values.yaml 

Install eksctl - https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html

Install helm 
https://helm.sh/docs/intro/install/

NodeSelector
https://kubernetes.io/docs/concepts/scheduling-eviction/assign-pod-node/


eksctl manage nodegroup 
https://eksctl.io/usage/spot-instances/
