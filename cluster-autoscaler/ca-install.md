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
    instanceTypes: ["c5.large","c5n.large","c5d.large","c5a.large","m5.large","m5d.large"]
    spot: true
    desiredCapacity: 1
    minSize: 1
    maxSize: 100
EOF
eksctl create nodegroup --config-file ${CLUSTER_NAME}-spot-nodegroup.yaml

aws autoscaling \
    describe-auto-scaling-groups \
    --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='${CLUSTER_NAME}']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" \
    --output table
```

In case if we do not configure the correct the value of max count of instances:

```bash
# we need the ASG name (double check if we have more than 1 ASG)
export ASG_NAME=$(aws autoscaling describe-auto-scaling-groups --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='${CLUSTER_NAME}']].AutoScalingGroupName" --output text | awk '{print $2}')

# increase max capacity up to 100
aws autoscaling \
    update-auto-scaling-group \
    --auto-scaling-group-name ${ASG_NAME} \
    --min-size 1 \
    --desired-capacity 2 \
    --max-size 100

# Check new values
aws autoscaling \
    describe-auto-scaling-groups \
    --query "AutoScalingGroups[? Tags[? (Key=='eks:cluster-name') && Value=='${CLUSTER_NAME}']].[AutoScalingGroupName, MinSize, MaxSize,DesiredCapacity]" \
    --output table
```

Creating an IAM policy for your service account that will allow your CA pod to interact with the autoscaling groups.

```bash
mkdir ~/environment/cluster-autoscaler

cat <<EoF > ~/environment/cluster-autoscaler/k8s-asg-policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Action": [
                "autoscaling:DescribeAutoScalingGroups",
                "autoscaling:DescribeAutoScalingInstances",
                "autoscaling:DescribeLaunchConfigurations",
                "autoscaling:DescribeTags",
                "autoscaling:SetDesiredCapacity",
                "autoscaling:TerminateInstanceInAutoScalingGroup",
                "ec2:DescribeLaunchTemplateVersions"
            ],
            "Resource": "*",
            "Effect": "Allow"
        }
    ]
}
EoF

aws iam create-policy   \
  --policy-name k8s-asg-policy \
  --policy-document file://~/environment/cluster-autoscaler/k8s-asg-policy.json


```

Finally, create an IAM role for the cluster-autoscaler Service Account in the kube-system namespace.

```bash
eksctl create iamserviceaccount \
    --name cluster-autoscaler \
    --namespace kube-system \
    --cluster "${CLUSTER_NAME}" \
    --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/k8s-asg-policy" \
    --approve \
    --override-existing-serviceaccounts

```

Make sure your service account with the ARN of the IAM role is annotated.

```bash
kubectl -n kube-system describe sa cluster-autoscaler
```

### Deploy the Cluster Autoscaler (CA)

Update cluster name

```bash
sed -i "s/REPLACE/${CLUSTER_NAME}/g" ~/environment/karpenter-demo/cluster-autoscaler/cluster-autoscaler-autodiscover.yaml
kubectl apply -f ~/environment/karpenter-demo/cluster-autoscaler/cluster-autoscaler-autodiscover.yaml

```
To prevent CA from removing nodes where its own pod is running, we will add the cluster-autoscaler.kubernetes.io/safe-to-evict annotation to its deployment with the following command:

```bash

kubectl patch deployment cluster-autoscaler \
  -n kube-system \
  -p '{"spec":{"template":{"metadata":{"annotations":{"cluster-autoscaler.kubernetes.io/safe-to-evict": "false"}}}}}'

```

finaly let's update the autoscaler image:

```bash
# we need to retrieve the latest docker image available for our EKS version
export K8S_VERSION=$(kubectl version --short | grep 'Server Version:' | sed 's/[^0-9.]*\([0-9.]*\).*/\1/' | cut -d. -f1,2)
export AUTOSCALER_VERSION=$(curl -s "https://api.github.com/repos/kubernetes/autoscaler/releases" | grep '"tag_name":' | sed -s 's/.*-\([0-9][0-9\.]*\).*/\1/' | grep -m1 ${K8S_VERSION})

kubectl set image deployment cluster-autoscaler \
  -n kube-system \
  cluster-autoscaler=k8s.gcr.io/autoscaling/cluster-autoscaler\:v${AUTOSCALER_VERSION}
```

Check the logs from auto-scaler

```bash
kubectl -n kube-system logs -f deployment.apps/cluster-autoscaler
```