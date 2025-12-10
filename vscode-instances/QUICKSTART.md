# VSCode Instances - Quick Start Guide

## 5-Minute Setup

### 1. Prerequisites Check
```bash
# Verify AWS CLI
aws sts get-caller-identity

# Create/verify key pair
aws ec2 describe-key-pairs --key-names YOUR-KEY-NAME
# OR create new one:
aws ec2 create-key-pair --key-name karpenter-demo-key \
  --query 'KeyMaterial' --output text > karpenter-demo-key.pem
chmod 400 karpenter-demo-key.pem
```

### 2. Deploy
```bash
cd vscode-instances/
./deploy.sh
```

**You'll be prompted for:**
- Key Pair name
- VSCode password (save this!)
- Instance type (press Enter for default: t3.xlarge)
- Volume size (press Enter for default: 50GB)
- Allowed CIDR (press Enter for default: 0.0.0.0/0)

**Wait 5-10 minutes...**

### 3. Access

Copy the URLs from output:
```
VSCode Instance 1: http://<IP-1>:8080
VSCode Instance 2: http://<IP-2>:8080
```

**Wait 2-3 more minutes after stack completes** for full setup, then:
1. Open URL in browser
2. Enter your VSCode password
3. Open Terminal in VSCode (Ctrl + `)

### 4. Verify Setup
```bash
# In VSCode terminal
kubectl version --client
eksctl version
aws sts get-caller-identity
echo $AWS_REGION

# Test fancy banner
lolbanner "Karpenter Demo"
```

### 5. Start Your Demo

Follow the main [README.md](../README.md) to:
1. Set environment variables
2. Create EKS cluster
3. Install Karpenter
4. Run demos

## Quick Commands

### Check Status
```bash
./status.sh
```

### Delete Everything
```bash
./delete-stack.sh  # Type 'delete' to confirm
```

### SSH Access (if needed)
```bash
ssh -i your-key.pem ec2-user@<ELASTIC-IP>
```

### Stop Instances (save costs)
```bash
# Get instance IDs from status.sh, then:
aws ec2 stop-instances --instance-ids i-xxx i-yyy

# Start again later:
aws ec2 start-instances --instance-ids i-xxx i-yyy
```

## Common Issues

**VSCode not loading?**
- Wait 2-3 minutes after stack creation
- Check: `./status.sh`
- SSH in and check: `sudo systemctl status code-server`

**Can't SSH?**
- Verify key pair: `aws ec2 describe-key-pairs --key-names YOUR-KEY`
- Check security group allows your IP
- Verify key file permissions: `chmod 400 your-key.pem`

**Tools missing?**
```bash
source ~/.bashrc
```

## Cost

**~$255/month** for 2x t3.xlarge instances running 24/7

**To save money:**
- Stop instances when not in use: ~$15/month (EBS + EIP only)
- Delete stack completely: $0
- Use t3.large instead: ~$120/month

## Two-Instance Demo Setup

Use both instances for impressive demos:

**Instance 1 - Monitoring Dashboard:**
```bash
# Terminal 1: Watch nodes scaling
watch 'kubectl get nodes -L node.kubernetes.io/instance-type,karpenter.sh/capacity-type'

# Terminal 2: Karpenter logs
kubectl logs -f -n kube-system -l app.kubernetes.io/name=karpenter -c controller

# Terminal 3: kube-ops-view
kubectl port-forward -n kube-ops-view svc/kube-ops-view 8080:80
```

**Instance 2 - Workload Execution:**
```bash
# Deploy test workloads
cd ~/workspace/karpenter-demo/karpenter-demo01
kubectl apply -f 02-1-kr-demand-nodepool.yaml
kubectl apply -f 02-4-kr-600pods-splitload.yaml

# High-load test
cd ~/workspace/karpenter-demo/high-load
./create.workload.sh 3000 500
```

## What's Included?

✅ **code-server** (VSCode in browser)
✅ **kubectl, eksctl, helm** (latest versions)
✅ **AWS CLI v2** with configured IAM role
✅ **k9s** (Kubernetes TUI)
✅ **krew** + plugins (resource-capacity, ctx, ns)
✅ **Docker** ready to use
✅ **All kubectl aliases** from cloud9-config.md
✅ **figlet + lolcat** for demo banners
✅ **fzf, jq, and more** utilities
✅ **Demo repository** cloned in ~/workspace
✅ **Environment variables** auto-configured

## Next Steps

👉 Read the full [README.md](README.md) for detailed documentation
👉 Follow the main [Karpenter Demo README](../README.md) for cluster setup
👉 Explore the [CloudFormation template](cloudformation.yaml) to customize
