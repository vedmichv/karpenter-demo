# VSCode EC2 Instances for Karpenter Demo

This directory contains CloudFormation templates and scripts to deploy two VSCode EC2 instances configured for running Karpenter demos on AWS EKS.

## Overview

The CloudFormation stack creates:

- **2 EC2 instances** running Amazon Linux 2023 (default: t3.xlarge)
- **code-server** (VSCode in the browser) accessible via HTTP on port 8080
- **All tools from cloud9-config.md** pre-installed:
  - kubectl, eksctl, helm, aws-cli v2
  - k9s, krew, kubectl plugins (resource-capacity)
  - Docker, jq, fzf, kubectx/kubens
  - figlet, lolcat (for demo banners)
- **IAM Role** with full permissions for EKS, EC2, IAM, CloudFormation
- **Security Group** allowing SSH (22) and VSCode (8080) access
- **Elastic IPs** for stable public access
- **50GB EBS volumes** (configurable) with gp3 storage

## Prerequisites

1. **AWS CLI** installed and configured
2. **EC2 Key Pair** in your target region
   ```bash
   # Create a new key pair if needed
   aws ec2 create-key-pair --key-name karpenter-demo-key \
     --query 'KeyMaterial' --output text > karpenter-demo-key.pem
   chmod 400 karpenter-demo-key.pem
   ```
3. **Appropriate IAM permissions** to create CloudFormation stacks

## Quick Start

### 1. Deploy the Stack

```bash
cd vscode-instances/
chmod +x *.sh
./deploy.sh
```

The script will prompt you for:
- EC2 Key Pair name
- VSCode password (min 8 characters)
- Instance type (default: t3.xlarge)
- EBS volume size (default: 50GB)
- Allowed CIDR for access (default: 0.0.0.0/0)

**Deployment takes 5-10 minutes.** The script will wait for completion and display access URLs.

### 2. Access VSCode

After deployment completes, wait 2-3 additional minutes for instance setup to finish, then:

1. Open the VSCode URL from the output: `http://<ELASTIC-IP>:8080`
2. Enter the password you set during deployment
3. You'll have a fully configured VSCode environment with terminal access

### 3. Verify Setup

SSH into an instance to verify:
```bash
ssh -i your-key.pem ec2-user@<ELASTIC-IP>

# Verify tools
kubectl version --client
eksctl version
helm version
aws --version
k9s version

# Check environment variables
echo $AWS_REGION
echo $ACCOUNT_ID

# Test kubectl aliases
k get nodes  # should work once you connect to a cluster
```

## Managing the Stack

### Check Stack Status

```bash
./status.sh
```

Shows:
- Stack creation/update status
- Output values (URLs, IPs)
- Instance states and details
- Recent CloudFormation events

### Delete the Stack

```bash
./delete-stack.sh
```

**Warning:** This permanently deletes all instances and data!

### Update the Stack

If you need to modify parameters:

```bash
aws cloudformation update-stack \
  --stack-name karpenter-demo-vscode \
  --template-body file://cloudformation.yaml \
  --parameters ParameterKey=InstanceType,ParameterValue=c5.2xlarge \
  --capabilities CAPABILITY_NAMED_IAM
```

## CloudFormation Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `InstanceType` | `t3.xlarge` | EC2 instance type (t3.large, t3.xlarge, c5.2xlarge, etc.) |
| `KeyPairName` | (required) | EC2 Key Pair for SSH access |
| `VSCodePassword` | (required) | Password for VSCode web interface (min 8 chars) |
| `VolumeSize` | `50` | EBS volume size in GB (30-500) |
| `AllowedSSHCIDR` | `0.0.0.0/0` | CIDR block for SSH/VSCode access |

## Stack Outputs

| Output | Description |
|--------|-------------|
| `VSCode1URL` | VSCode Instance 1 web interface URL |
| `VSCode2URL` | VSCode Instance 2 web interface URL |
| `VSCode1SSH` | SSH command for Instance 1 |
| `VSCode2SSH` | SSH command for Instance 2 |
| `VSCode1PublicIP` | Public IP of Instance 1 |
| `VSCode2PublicIP` | Public IP of Instance 2 |
| `SecurityGroupId` | Security Group ID |
| `IAMRoleArn` | IAM Role ARN |

## Using with Karpenter Demo

Once your instances are ready:

### 1. Clone the Demo Repository (already done in ~/workspace)

```bash
cd ~/workspace/karpenter-demo
```

### 2. Set Environment Variables

```bash
export KARPENTER_NAMESPACE="kube-system"
export KARPENTER_VERSION="1.2.1"
export K8S_VERSION="1.32"
export CLUSTER_NAME="karpenter-demo-$(date +%y-%m-%d-%H)"
export AWS_DEFAULT_REGION="$AWS_REGION"
export AWS_ACCOUNT_ID="$ACCOUNT_ID"
```

### 3. Create EKS Cluster

Follow the main [README.md](../README.md) to create your EKS cluster with Karpenter.

### 4. Run Demos

Use both instances to demonstrate:
- **Instance 1**: Run monitoring tools (kube-ops-view, watch commands)
- **Instance 2**: Execute workload deployments and tests

Example monitoring setup on Instance 1:
```bash
# Terminal 1: Watch nodes
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type'

# Terminal 2: Watch pods
watch 'kubectl get pods -A'

# Terminal 3: Karpenter logs
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller
```

Example workload testing on Instance 2:
```bash
cd ~/workspace/karpenter-demo/karpenter-demo01
kubectl apply -f 01-kr-start-10pods.yaml

# High load test
cd ~/workspace/karpenter-demo/high-load
./create.workload.sh 3000 500
```

## Customization

### Instance Type Recommendations

| Use Case | Instance Type | vCPUs | Memory | Cost (approx) |
|----------|--------------|-------|--------|---------------|
| Light demos | t3.large | 2 | 8 GB | $0.08/hr |
| **Recommended** | **t3.xlarge** | **4** | **16 GB** | **$0.17/hr** |
| Heavy workloads | t3.2xlarge | 8 | 32 GB | $0.33/hr |
| Compute intensive | c5.2xlarge | 8 | 16 GB | $0.34/hr |

### Security Best Practices

For production or sensitive demos:

1. **Restrict access CIDR**
   ```bash
   # Only allow your IP
   ALLOWED_CIDR="$(curl -s ifconfig.me)/32"
   ```

2. **Use HTTPS with SSL certificates**
   - Configure code-server with Let's Encrypt
   - Update Security Group to allow 443 only

3. **Enable CloudWatch logging**
   - Monitor instance metrics
   - Set up alarms for unusual activity

### Adding Custom Tools

Edit the UserData section in `cloudformation.yaml` to add additional tools:

```bash
# Example: Install additional tools
su - ec2-user -c '
  # Install terraform
  wget https://releases.hashicorp.com/terraform/1.5.0/terraform_1.5.0_linux_amd64.zip
  unzip terraform_1.5.0_linux_amd64.zip
  sudo mv terraform /usr/local/bin/

  # Install additional kubectl plugins
  kubectl krew install stern
  kubectl krew install tree
'
```

## Troubleshooting

### Instance not accessible after 10 minutes

Check CloudFormation events:
```bash
./status.sh
```

Common issues:
- **Key pair not found**: Ensure key pair exists in the correct region
- **IAM permission denied**: Check your AWS credentials have sufficient permissions
- **Security Group rules**: Verify your IP is allowed in AllowedSSHCIDR

### VSCode not loading

1. **SSH into the instance**
   ```bash
   ssh -i your-key.pem ec2-user@<ELASTIC-IP>
   ```

2. **Check code-server status**
   ```bash
   sudo systemctl status code-server
   journalctl -u code-server -f
   ```

3. **Check setup logs**
   ```bash
   cat /var/log/user-data.log
   tail -100 /var/log/cloud-init-output.log
   ```

4. **Restart code-server**
   ```bash
   sudo systemctl restart code-server
   ```

### Tools not working

Source the bash profile:
```bash
source ~/.bashrc
```

Check PATH:
```bash
echo $PATH
which kubectl eksctl helm
```

## Cost Estimation

### Monthly Cost (approximate, us-east-1 rates)

| Component | Cost |
|-----------|------|
| 2x t3.xlarge (24/7) | ~$240/month |
| 2x 50GB EBS gp3 | ~$8/month |
| 2x Elastic IPs | ~$7.20/month |
| Data transfer | Variable |
| **Total** | **~$255/month** |

**Recommendations:**
- Stop instances when not in use (EBS and EIP still billed)
- Use t3.large for cost savings (~$120/month for 2 instances)
- Delete stack completely when demo is complete

### Stopping Instances (Cost Savings)

```bash
# Get instance IDs
INSTANCE_IDS=$(aws cloudformation describe-stack-resources \
  --stack-name karpenter-demo-vscode \
  --query 'StackResources[?ResourceType==`AWS::EC2::Instance`].PhysicalResourceId' \
  --output text)

# Stop instances
aws ec2 stop-instances --instance-ids $INSTANCE_IDS

# Start instances
aws ec2 start-instances --instance-ids $INSTANCE_IDS
```

Note: Elastic IPs will remain stable after stopping/starting.

## Architecture Diagram

```
┌─────────────────────────────────────────────┐
│           AWS Cloud (Your Region)           │
│                                             │
│  ┌────────────────────────────────────┐    │
│  │        Default VPC                  │    │
│  │                                     │    │
│  │  ┌───────────────────────────┐     │    │
│  │  │   Security Group          │     │    │
│  │  │   - SSH (22)              │     │    │
│  │  │   - VSCode (8080)         │     │    │
│  │  │   - HTTPS (443)           │     │    │
│  │  └───────────────────────────┘     │    │
│  │            ↓        ↓               │    │
│  │  ┌─────────────┐  ┌─────────────┐  │    │
│  │  │ VSCode-1    │  │ VSCode-2    │  │    │
│  │  │             │  │             │  │    │
│  │  │ t3.xlarge   │  │ t3.xlarge   │  │    │
│  │  │ AL2023      │  │ AL2023      │  │    │
│  │  │ code-server │  │ code-server │  │    │
│  │  │ 50GB EBS    │  │ 50GB EBS    │  │    │
│  │  └─────────────┘  └─────────────┘  │    │
│  │       ↓                  ↓          │    │
│  │  ┌─────────┐        ┌─────────┐    │    │
│  │  │  EIP-1  │        │  EIP-2  │    │    │
│  │  └─────────┘        └─────────┘    │    │
│  │                                     │    │
│  │  ┌───────────────────────────┐     │    │
│  │  │   IAM Role                │     │    │
│  │  │   - EKS Full Access       │     │    │
│  │  │   - EC2/IAM for Karpenter │     │    │
│  │  │   - CloudFormation        │     │    │
│  │  └───────────────────────────┘     │    │
│  └────────────────────────────────────┘    │
└─────────────────────────────────────────────┘
```

## Integration with Main Repository

This VSCode setup integrates with the main Karpenter demo:

1. **Replaces Cloud9** - Provides equivalent functionality
2. **Same tools** - All tools from cloud9-config.md pre-installed
3. **Same demo flow** - Follow main README.md instructions
4. **Better for demos** - Two instances allow parallel monitoring/testing
5. **Cost control** - Can stop/start or delete when not in use

## Support

For issues or questions:
1. Check troubleshooting section above
2. Review CloudFormation events: `./status.sh`
3. Check instance logs: SSH in and run `cat /var/log/user-data.log`
4. Review main repository issues

## License

This is part of the karpenter-demo repository. Use according to repository license.
