# AWS Cleanup Dry-Run Plan
## Account: <YOUR_AWS_ACCOUNT_ID>
## Generated: 2025-11-21T14:33:00+01:00

---

## PROTECTED RESOURCES (WILL NOT DELETE)

| Resource Type | Resource ID | Region | Name/Tags | Protection Reason |
|--------------|-------------|--------|-----------|-------------------|
| S3 Bucket | cloudtrail-awslogs-<ACCOUNT_ID>-xxxxx-do-not-delete | global | - | Name contains "do-not-delete" |
| S3 Bucket | do-not-delete-gatedgarden-audit-<ACCOUNT_ID> | global | - | Name contains "do-not-delete" |
| S3 Bucket | do-not-delete-profiler-metadata-<ACCOUNT_ID> | global | - | Name contains "do-not-delete" |
| VPC | vpc-* (20 default VPCs) | all regions | IsDefault=true | Default VPCs |

---

## RESOURCES TO DELETE (Ordered by Dependency)

### Phase 1: EKS Cluster Cleanup (eu-north-1)

#### 1.1 EKS Add-ons
| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| EKS Addon | coredns | eu-north-1 | Cluster: karpenter-demo-25-11-21-01 | Delete first |
| EKS Addon | eks-pod-identity-agent | eu-north-1 | Cluster: karpenter-demo-25-11-21-01 | Delete first |
| EKS Addon | kube-proxy | eu-north-1 | Cluster: karpenter-demo-25-11-21-01 | Delete first |
| EKS Addon | metrics-server | eu-north-1 | Cluster: karpenter-demo-25-11-21-01 | Delete first |
| EKS Addon | vpc-cni | eu-north-1 | Cluster: karpenter-demo-25-11-21-01 | Delete first |

#### 1.2 EKS Node Groups
| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| EKS NodeGroup | karpenter-demo-25-11-21-01-ng | eu-north-1 | Cluster: karpenter-demo-25-11-21-01 | Delete after add-ons |

#### 1.3 EKS Cluster
| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| EKS Cluster | karpenter-demo-25-11-21-01 | eu-north-1 | Status: ACTIVE, No deletion protection | Delete after node groups |

### Phase 2: EC2 Resources (eu-north-1)

#### 2.1 EC2 Instances
| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| EC2 Instance | i-05281480b483fd476 | eu-north-1 | karpenter-demo-vscode-VSCode-2 | Running, Purpose=Karpenter-Demo |
| EC2 Instance | i-0f51f6e0865fb2df5 | eu-north-1 | karpenter-demo-vscode-VSCode-1 | Running, Purpose=Karpenter-Demo |
| EC2 Instance | i-065dbca4f1570f030 | eu-north-1 | EKS node | Running, part of node group |
| EC2 Instance | i-08007d861a5d98681 | eu-north-1 | EKS node | Running, part of node group |

#### 2.2 Load Balancers
| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| Classic ELB | af3f7e718289146429123561b8058381 | eu-north-1 | DNS: af3f7e718289146429123561b8058381-1941354891.eu-north-1.elb.amazonaws.com | Kubernetes-created |

#### 2.3 Auto Scaling Groups
| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| ASG | eks-karpenter-demo-25-11-21-01-ng-54cd5308-6640-fb1d-cc8c-543e2c6be83d | eu-north-1 | EKS node group ASG | Delete after node group deletion |

#### 2.4 EBS Volumes
| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| EBS Volume | vol-07e3d78fa9093de3f | eu-north-1 | in-use | VSCode instance volume |
| EBS Volume | vol-07feb295638b5d394 | eu-north-1 | in-use | EKS node volume |
| EBS Volume | vol-0dcdecd6b811346eb | eu-north-1 | in-use | VSCode instance volume |
| EBS Volume | vol-0e254699a3d9ff68f | eu-north-1 | in-use | EKS node volume |

### Phase 3: CloudFormation Stacks (eu-north-1)

| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| CFN Stack | karpenter-demo-vscode | eu-north-1 | Status: CREATE_COMPLETE | Delete stack (will clean up VSCode instances, IAM roles, SGs) |
| CFN Stack | eksctl-karpenter-demo-25-11-21-01-podidentityrole-kube-system-karpenter | eu-north-1 | Status: CREATE_COMPLETE | Delete after EKS cluster |
| CFN Stack | eksctl-karpenter-demo-25-11-21-01-nodegroup-karpenter-demo-25-11-21-01-ng | eu-north-1 | Status: CREATE_COMPLETE | Delete after node group |
| CFN Stack | eksctl-karpenter-demo-25-11-21-01-addon-vpc-cni | eu-north-1 | Status: CREATE_COMPLETE | Delete after add-ons |
| CFN Stack | eksctl-karpenter-demo-25-11-21-01-cluster | eu-north-1 | Status: CREATE_COMPLETE | Delete after EKS cluster |
| CFN Stack | Karpenter-karpenter-demo-25-11-21-01 | eu-north-1 | Status: CREATE_COMPLETE | Delete after EKS cluster |

### Phase 4: VPC Resources (eu-north-1)

#### 4.1 EKS VPC
| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| VPC | vpc-0c54ccbb5997622d3 | eu-north-1 | eksctl-karpenter-demo-25-11-21-01-cluster/VPC | Delete after all resources cleaned |

This VPC contains:
- 6 subnets
- 2 security groups (sg-002652a294f2ef6ef, sg-03fa38fe1246cc183)
- Internet Gateway, NAT Gateways, Route Tables, etc.

### Phase 5: Other VPC (us-west-2)

| Resource Type | Resource ID | Region | Name/Tags | Notes |
|--------------|-------------|--------|-----------|-------|
| VPC | vpc-00b927199d70a0df0 | us-west-2 | Name: main-vpc | Empty VPC, safe to delete |

---

## DELETION ORDER SUMMARY

1. **EKS Add-ons** (5 add-ons) - 2-3 minutes
2. **EKS Node Group** (1 node group) - 5-10 minutes
3. **EKS Cluster** (1 cluster) - 10-15 minutes
4. **Classic ELB** (1 load balancer) - 1 minute
5. **CloudFormation Stack: karpenter-demo-vscode** - 5 minutes (terminates 2 EC2 instances, cleans IAM, SGs)
6. **CloudFormation Stacks: EKS-related** (5 stacks) - 5-10 minutes
7. **Auto Scaling Group** (if not deleted by CFN) - 2 minutes
8. **EBS Volumes** (4 volumes, if not deleted by instance termination) - 1 minute
9. **VPC: vpc-0c54ccbb5997622d3** (eu-north-1) - Delete all sub-resources first:
   - ENIs, NAT Gateways, Internet Gateways, Route Tables, Subnets, Security Groups
   - Then delete VPC - 5 minutes
10. **VPC: vpc-00b927199d70a0df0** (us-west-2) - 2 minutes

**Estimated Total Time: 40-60 minutes**

---

## COST SAVINGS ESTIMATE

### Compute
- 2x t3.xlarge EC2 (VSCode): ~$0.33/hr × 2 = $0.66/hr → **$475/month**
- 2x EKS nodes (managed node group): ~$0.20/hr × 2 = $0.40/hr → **$288/month**
- EKS control plane: **$73/month**

### Storage
- 4x EBS volumes (~50GB each): **$40/month**

### Networking
- NAT Gateway: **$32/month**
- Data transfer: **~$10-50/month**

### Total Estimated Monthly Savings: **$918 - $958/month**

---

## RISKS & WARNINGS

⚠️ **CRITICAL WARNINGS:**
1. All 3 S3 buckets are PROTECTED and will NOT be deleted
2. Default VPCs in all regions will NOT be deleted
3. EKS cluster deletion is IRREVERSIBLE - all Kubernetes workloads will be lost
4. CloudFormation stack deletion will remove IAM roles/policies created by those stacks
5. VPC deletion will fail if any resources are still attached

---

## NEXT STEPS

1. **Review this plan carefully**
2. **Verify protected resources are correct**
3. **Reply with: PROCEED WITH DELETION** to execute
4. **Or reply with: CANCEL** to abort

