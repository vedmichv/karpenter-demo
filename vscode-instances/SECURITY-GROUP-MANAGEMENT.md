# Security Group Management

## Overview

For security best practices, the VSCode instances are deployed with a **default-deny security group** that blocks ALL inbound traffic. This means after deployment, you **cannot access** the instances until you manually open the required ports.

## Security Philosophy

**Default Deny** - Start with no access and explicitly grant only what's needed:
- ✅ Prevents accidental exposure of services
- ✅ Forces conscious decision about network access
- ✅ Follows AWS security best practices
- ✅ Reduces attack surface

## Required Ports

To use the VSCode instances, you need to open these ports:

| Port | Protocol | Purpose | Required |
|------|----------|---------|----------|
| 8080 | TCP | VSCode web interface | ✅ Yes |
| 22 | TCP | SSH access | ⚠️ Optional (for troubleshooting) |
| 443 | TCP | HTTPS (if configured) | ⚠️ Optional |

## Quick Start - Open Ports for Your IP

### Option 1: Using the Helper Script (Recommended)

```bash
# Open VSCode port (8080) for your current IP
./open-ports.sh

# This automatically:
# 1. Detects your public IP
# 2. Finds the security group
# 3. Adds ingress rules for port 8080 and 22
```

### Option 2: Using AWS Console

1. Open [EC2 Security Groups](https://console.aws.amazon.com/ec2/home#SecurityGroups)
2. Find security group: `karpenter-demo-vscode-VSCodeSG` (or your stack name)
3. Click **Actions** → **Edit inbound rules**
4. Click **Add rule**:
   - **Type:** Custom TCP
   - **Port range:** 8080
   - **Source:** My IP (automatically detects your IP)
   - **Description:** VSCode web access
5. Click **Add rule** again for SSH:
   - **Type:** SSH
   - **Port range:** 22
   - **Source:** My IP
   - **Description:** SSH access
6. Click **Save rules**

### Option 3: Using AWS CLI

```bash
# Get your security group ID
STACK_NAME="karpenter-demo-vscode"
SG_ID=$(aws cloudformation describe-stack-resources \
  --stack-name $STACK_NAME \
  --query 'StackResources[?LogicalResourceId==`VSCodeSecurityGroup`].PhysicalResourceId' \
  --output text)

# Get your public IP
MY_IP=$(curl -s https://checkip.amazonaws.com)

# Open port 8080 for VSCode
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr ${MY_IP}/32 \
  --description "VSCode web access from my IP"

# Open port 22 for SSH (optional)
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 22 \
  --cidr ${MY_IP}/32 \
  --description "SSH access from my IP"
```

## Common Access Scenarios

### Scenario 1: Single User (Your IP Only)

**Most Secure** - Restricts access to only your IP address.

```bash
MY_IP=$(curl -s https://checkip.amazonaws.com)

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr ${MY_IP}/32
```

### Scenario 2: Team Access (Company Network)

Allow access from your company's IP range.

```bash
# Example: Company network is 203.0.113.0/24
COMPANY_CIDR="203.0.113.0/24"

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr $COMPANY_CIDR \
  --description "VSCode access from company network"
```

### Scenario 3: Public Demo (Temporary Open Access)

⚠️ **Use with caution** - Opens access to anyone. Only use for public demos.

```bash
# CAUTION: This allows access from anywhere!
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr 0.0.0.0/0 \
  --description "Temporary public access for demo"
```

**Remember to remove this rule after your demo!**

### Scenario 4: VPN Access Only

Allow access only through your VPN exit IPs.

```bash
# Example: VPN exit IPs
VPN_IP_1="198.51.100.10/32"
VPN_IP_2="198.51.100.11/32"

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr $VPN_IP_1 \
  --description "VSCode via VPN 1"

aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr $VPN_IP_2 \
  --description "VSCode via VPN 2"
```

## Managing Rules

### List Current Rules

```bash
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --query 'SecurityGroups[0].IpPermissions' \
  --output table
```

### Remove a Specific Rule

```bash
# Remove rule for port 8080 from specific IP
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr 203.0.113.45/32
```

### Remove All Inbound Rules (Lockdown)

```bash
# Get all current rules
RULES=$(aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json)

# Revoke all rules
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --ip-permissions "$RULES"
```

## Advanced Scenarios

### Dynamic IP Management

If your IP changes frequently (home internet, mobile), use this script:

```bash
# Save as update-my-access.sh
#!/bin/bash

SG_ID="sg-xxxxx"  # Your security group ID
OLD_IP_FILE=~/.vscode-sg-ip

# Get current IP
NEW_IP=$(curl -s https://checkip.amazonaws.com)

if [ -f "$OLD_IP_FILE" ]; then
    OLD_IP=$(cat $OLD_IP_FILE)

    # Remove old IP rule
    aws ec2 revoke-security-group-ingress \
      --group-id $SG_ID \
      --protocol tcp \
      --port 8080 \
      --cidr ${OLD_IP}/32 2>/dev/null || true
fi

# Add new IP rule
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr ${NEW_IP}/32 \
  --description "VSCode access - updated $(date)"

echo $NEW_IP > $OLD_IP_FILE
echo "Access updated for IP: $NEW_IP"
```

### Time-Based Access (Using Lambda)

For scheduled access control, create a Lambda function:

```python
import boto3
from datetime import datetime, time

ec2 = boto3.client('ec2')
SG_ID = 'sg-xxxxx'

def lambda_handler(event, context):
    current_time = datetime.now().time()

    # Open access during business hours (9 AM - 6 PM)
    if time(9, 0) <= current_time <= time(18, 0):
        # Add rules
        ec2.authorize_security_group_ingress(
            GroupId=SG_ID,
            IpPermissions=[{
                'IpProtocol': 'tcp',
                'FromPort': 8080,
                'ToPort': 8080,
                'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
            }]
        )
    else:
        # Remove rules
        ec2.revoke_security_group_ingress(
            GroupId=SG_ID,
            IpPermissions=[{
                'IpProtocol': 'tcp',
                'FromPort': 8080,
                'ToPort': 8080,
                'IpRanges': [{'CidrIp': '0.0.0.0/0'}]
            }]
        )
```

Schedule with EventBridge to run every hour.

## Security Best Practices

### 1. Use /32 CIDR for Single IPs

Always use `/32` suffix for single IP addresses:
- ✅ `203.0.113.45/32` - Single IP
- ❌ `203.0.113.45` - Might be interpreted as network

### 2. Add Descriptive Descriptions

Always add clear descriptions to rules:
```bash
--description "VSCode access for John - expires 2025-01-31"
```

### 3. Regular Audits

Schedule monthly reviews of security group rules:
```bash
# List all rules with IPs
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[*].CidrIp,IpRanges[*].Description]' \
  --output table
```

### 4. Use Tags for Tracking

```bash
# Tag rules for tracking
aws ec2 create-tags \
  --resources $SG_ID \
  --tags Key=Owner,Value=TeamA Key=Purpose,Value=KarpenterDemo Key=ExpiryDate,Value=2025-02-28
```

### 5. Temporary Access Pattern

For temporary demos:
1. Open port before demo
2. Do the demo
3. **Immediately close port after**

```bash
# Before demo
./open-ports.sh

# After demo
./close-ports.sh
```

### 6. Use AWS Systems Manager Session Manager Instead of SSH

Instead of opening port 22, use Session Manager for secure access:
```bash
aws ssm start-session --target <instance-id>
```

No security group rule needed!

## Troubleshooting

### Can't Access VSCode After Deployment

**Problem:** Browser shows "Connection refused" or timeout on http://\<IP\>:8080

**Solution:**
1. Check security group has rule for port 8080
2. Verify rule allows your current IP
3. Confirm instance is running: `aws ec2 describe-instances`
4. Check code-server is running: SSH in and run `sudo systemctl status code-server`

### My IP Changed and I Lost Access

**Problem:** Rules have old IP, you can't access anymore

**Solution 1 - AWS Console:**
1. Open EC2 console on your phone or different network
2. Update security group rules

**Solution 2 - AWS CloudShell:**
1. Open [AWS CloudShell](https://console.aws.amazon.com/cloudshell/home)
2. Run the update commands from there

**Solution 3 - Session Manager:**
```bash
# Access via Session Manager (no port 22 needed)
aws ssm start-session --target <instance-id>

# Update security group from inside instance
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr $(curl -s https://checkip.amazonaws.com)/32
```

### Rule Already Exists Error

**Problem:** `aws ec2 authorize-security-group-ingress` returns error about duplicate rule

**Solution:**
```bash
# Remove existing rule first
aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr <old-ip>/32

# Then add new rule
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --cidr <new-ip>/32
```

## Helper Scripts

Use the provided scripts in this directory:

```bash
# Open ports for your current IP
./open-ports.sh

# Close all ports (emergency lockdown)
./close-ports.sh

# Show current rules
./show-rules.sh

# Update IP (removes old, adds new)
./update-my-ip.sh
```

## Emergency Procedures

### Complete Lockdown (Security Incident)

```bash
# Remove ALL inbound rules immediately
SG_ID=$(aws cloudformation describe-stack-resources \
  --stack-name karpenter-demo-vscode \
  --query 'StackResources[?LogicalResourceId==`VSCodeSecurityGroup`].PhysicalResourceId' \
  --output text)

RULES=$(aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --query 'SecurityGroups[0].IpPermissions' \
  --output json)

aws ec2 revoke-security-group-ingress \
  --group-id $SG_ID \
  --ip-permissions "$RULES"

echo "All inbound access blocked"
```

### Stop Instances

```bash
# Stop instances to completely cut access
INSTANCE_IDS=$(aws cloudformation describe-stack-resources \
  --stack-name karpenter-demo-vscode \
  --query 'StackResources[?ResourceType==`AWS::EC2::Instance`].PhysicalResourceId' \
  --output text)

aws ec2 stop-instances --instance-ids $INSTANCE_IDS
```

## Compliance and Auditing

### Export Security Group Rules for Audit

```bash
# Export to JSON
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --output json > security-group-audit-$(date +%Y%m%d).json

# Export to CSV (simplified)
aws ec2 describe-security-groups \
  --group-ids $SG_ID \
  --query 'SecurityGroups[0].IpPermissions[*].[IpProtocol,FromPort,ToPort,IpRanges[0].CidrIp,IpRanges[0].Description]' \
  --output text > security-group-audit-$(date +%Y%m%d).csv
```

### CloudWatch Alarms for Unauthorized Changes

Create an alarm for security group modifications:

```bash
# This requires CloudTrail to be enabled
# Will alert on any security group changes
```

## FAQ

**Q: Why not just open 0.0.0.0/0 for demos?**
A: While convenient, this exposes your VSCode instance to the entire internet. Anyone can access it if they find your IP. Use temporarily only if needed, and close immediately after.

**Q: Can I use AWS Security Group prefix lists?**
A: Yes! For AWS service access, use managed prefix lists:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --ip-permissions IpProtocol=tcp,FromPort=8080,ToPort=8080,PrefixListIds=[{PrefixListId=pl-xxxxx}]
```

**Q: How do I allow access from another AWS account?**
A: You can reference another account's security group:
```bash
aws ec2 authorize-security-group-ingress \
  --group-id $SG_ID \
  --protocol tcp \
  --port 8080 \
  --source-group $OTHER_SG_ID \
  --group-owner $OTHER_ACCOUNT_ID
```

**Q: Can I automate this with Terraform/CDK?**
A: Yes! Consider using infrastructure-as-code to manage security group rules with approval workflows.

## Related Documentation

- [AWS Security Group Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [AWS Security Group Rules Reference](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/security-group-rules-reference.html)
- [AWS Systems Manager Session Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
