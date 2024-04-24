# karpenter-demo

## Process of installation EKS cluster with Karpenter

To configure your cloud9 environment use the doc [cloud9-configuration](https://github.com/vedmichv/karpenter-demo/blob/main/cloud9-config.md)

Link to karpenter cluster http://ae11d3da8ab5d4dd2a765c3a28d2a6b4-1193830627.eu-north-1.elb.amazonaws.com/
Link to high-load karpenter cluster 

The best way to install cluster use the official documentation https://karpenter.sh/v0.27.2/getting-started/getting-started-with-karpenter/

Define variables:

```bash
export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="0.36.0"
export K8S_VERSION="1.29"


export CLUSTER_NAME="kr-astana-01"
export AWS_PARTITION="aws" 
export AWS_DEFAULT_REGION="eu-north-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export TEMPOUT="$(mktemp)"
export ARM_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2-arm64/recommended/image_id --query Parameter.Value --output text)"
export AMD_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2/recommended/image_id --query Parameter.Value --output text)"
export GPU_AMI_ID="$(aws ssm get-parameter --name /aws/service/eks/optimized-ami/${K8S_VERSION}/amazon-linux-2-gpu/recommended/image_id --query Parameter.Value --output text)"

# check that we correctly configure our vars
echo $KARPENTER_VERSION $CLUSTER_NAME $AWS_DEFAULT_REGION $AWS_ACCOUNT_ID
```

We use the bigger size of EC2 instance: `c5.2xlarge` to cover our high load example

#### Use CloudFormation to set up the infrastructure needed by the EKS cluster.

```bash
curl -fsSL https://raw.githubusercontent.com/aws/karpenter-provider-aws/v"${KARPENTER_VERSION}"/website/content/en/preview/getting-started/getting-started-with-karpenter/cloudformation.yaml  > "${TEMPOUT}" \
&& aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}"
```

#### Deploy EKS cluster 

```bash
eksctl create cluster -f - <<EOF
---
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig
metadata:
  name: ${CLUSTER_NAME}
  region: ${AWS_DEFAULT_REGION}
  version: "${K8S_VERSION}"
  tags:
    karpenter.sh/discovery: ${CLUSTER_NAME}

iam:
  withOIDC: true
  podIdentityAssociations:
  - namespace: "${KARPENTER_NAMESPACE}"
    serviceAccountName: karpenter
    roleName: ${CLUSTER_NAME}-karpenter
    permissionPolicyARNs:
    - arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}

iamIdentityMappings:
- arn: "arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}"
  username: system:node:{{EC2PrivateDNSName}}
  groups:
  - system:bootstrappers
  - system:nodes

managedNodeGroups:
- instanceType: c5.2xlarge
  amiFamily: AmazonLinux2
  name: ${CLUSTER_NAME}-ng
  desiredCapacity: 2
  minSize: 1
  maxSize: 10

addons:
- name: eks-pod-identity-agent
EOF

export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name "${CLUSTER_NAME}" --query "cluster.endpoint" --output text)"
export KARPENTER_IAM_ROLE_ARN="arn:${AWS_PARTITION}:iam::${AWS_ACCOUNT_ID}:role/${CLUSTER_NAME}-karpenter"

echo "${CLUSTER_ENDPOINT} ${KARPENTER_IAM_ROLE_ARN}"

```

If never use spot on the account run the command
```bash
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com || true
# If the role has already been successfully created, you will see:
# An error occurred (InvalidInput) when calling the CreateServiceLinkedRole operation: Service role name AWSServiceRoleForEC2Spot has been taken in this account, please try a different suffix.
```

To avoid issue with ECR - logout 
```bash
helm registry logout public.ecr.aws
```

### Kube-ops-view is required for the demo

#### Metric server:

```bash
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl get deployment metrics-server -n kube-system
```

#### Kube-Ops-View

```bash
cd ~/environment/karpenter-demo/kube-ops-view/
kubectl apply -k deploy 
kubectl get pod,svc,sa
cd ~/environment
```


## Install karpenter Helm Chart

Dry-run chart - check that HELM chart is deployable

```bash
helm install --debug --dry-run karpenter oci://public.ecr.aws/karpenter/karpenter --version "${KARPENTER_VERSION}" --namespace "${KARPENTER_NAMESPACE}" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=2 \
  --set controller.resources.requests.memory=2Gi \
  --set controller.resources.limits.cpu=4 \
  --set controller.resources.limits.memory=4Gi
```


Deploy Karpenter

```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version "${KARPENTER_VERSION}" --namespace "${KARPENTER_NAMESPACE}" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=2 \
  --set controller.resources.requests.memory=2Gi \
  --set controller.resources.limits.cpu=4 \
  --set controller.resources.limits.memory=4Gi \
  --wait
```

### NodePool default with spot instances and consolidation is enabled


```bash
cat <<EOF | envsubst | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h 
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2 # Amazon Linux 2
  role: "KarpenterNodeRole-${CLUSTER_NAME}" # replace with your cluster name
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}" # replace with your cluster name
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}" # replace with your cluster name
  amiSelectorTerms:
    - id: "${ARM_AMI_ID}"
    - id: "${AMD_AMI_ID}"
EOF


```



### High load 
- restriction not more than 200 pods per node 
- consolidation is enabled
- only spot instances

```bash

cat <<EOF | envsubst | kubectl apply -f -
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1beta1
        kind: EC2NodeClass
        name: default
      kubelet:
        maxPods: 200
  limits:
    cpu: 5000
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h # 30 * 24h = 720h
---
apiVersion: karpenter.k8s.aws/v1beta1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2 # Amazon Linux 2
  role: "KarpenterNodeRole-${CLUSTER_NAME}" # replace with your cluster name
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}" # replace with your cluster name
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}" # replace with your cluster name
  amiSelectorTerms:
    - id: "${ARM_AMI_ID}"
    - id: "${AMD_AMI_ID}"
EOF

### Run high load test

It will create 3000 pods with batch 500 pods per deployment. Resource request randomly selected from array: 
`CPU_OPTIONS=(250m 500m 750m 1 2)`
`MEM_OPTIONS=(128M 256M 512M 750M 1G)`


```bash
./create.workload.sh 3000 500
```

## Demo 1 - show Karpenter in action first 10 pod 
Deploy inflate deployment 
10 pod 
```bash
cd 
k apply -f 
```


60 pod - Demostrate consolidation 

```bash
# scale deployment
kubectl scale --replicas=60 deployment/inflate 
```

## Demo 2- Split load spot and on-demand isntances

The manifests located on kr-demo folder.  

watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'

### Usefull commands to check status of deployment

```bash
watch 'kubectl get deployment'
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type'
watch 'kubectl get deployments.apps | grep -v NAME | wc -l'
```


Get logs from Karpenter:

```bash
kubectl logs -f -n "${KARPENTER_NAMESPACE}" -l app.kubernetes.io/name=karpenter -c controller
```


Scale and other usefull commands 

```bash
# scale nodegroup
eksctl scale nodegroup --cluster=${CLUSTER_NAME} --nodes=2 --name=${CLUSTER_NAME}-ng
# to select the right instance
ec2-instance-selector -o one-line --service eks
ec2-instance-selector --memory 4 --vcpus 2 --cpu-architecture x86_64 -r us-east-1 -o table
# External plugin for kubernetes to show what the resources currently is used by cluster
kubectl resource-capacity --sort cpu.request
kubectl get no -L node.kubernetes.io/instance-type,kubernetes.io/arch,karpenter.sh/capacity-type 

```