# Finishline Karpenter Deployment on AWS EKS

This repository contains a complete, production-ready infrastructure-as-code solution for deploying [Karpenter](https://karpenter.sh/) on AWS EKS clusters with proper IAM role alignment, IRSA (IAM Roles for Service Accounts), and best practices for cost-optimized, high-performance node autoscaling.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [IAM Role Alignment](#iam-role-alignment)
- [Deployment Guide](#deployment-guide)
- [Configuration](#configuration)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

## Overview

Karpenter is an open-source autoscaling solution for Kubernetes that improves resource efficiency and cost by:

- **Dynamic node provisioning** - Automatically scales nodes based on workload demands
- **Bin packing** - Places pods efficiently to minimize resource waste
- **Multi-architecture support** - Supports both Arm64 and x86 instances
- **Spot instance integration** - Leverages spot instances for cost optimization
- **Fast scaling** - Scales nodes in seconds, not minutes

This deployment provides:

✅ **Aligned IAM & IRSA** - Service account roles properly map to AWS IAM roles via OIDC federation  
✅ **CloudFormation templates** - Fully defined IAM roles, policies, and instance profiles  
✅ **Helm charts** - Karpenter installation with service account binding  
✅ **Kubernetes manifests** - EC2NodeClass and NodePool with consistent resource references  
✅ **Automated scripts** - Complete deployment, verification, and cleanup workflows  
✅ **Production hardened** - Security best practices, error handling, and verification  
✅ **Version controlled** - All configurations externalized in config.env for repeatability  

## Architecture

```
┌─────────────────────────────────────────┐
│         EKS Cluster (finishline)       │
├─────────────────────────────────────────┤
│                                         │
│  ┌───────────────────────────────────┐ │
│  │  Karpenter Controller             │ │
│  │  (Manages Node Provisioning)      │ │
│  └───────────────────────────────────┘ │
│           ↓      ↓       ↓             │
│  ┌──────────────────────────────────┐  │
│  │  Karpenter-managed EC2 Nodes     │  │
│  │  (Auto-provisioned by Karpenter) │  │
│  └──────────────────────────────────┘  │
│                                         │
└─────────────────────────────────────────┘
         ↓
    CloudFormation
    ├─ Karpenter Controller IAM Role (IRSA)
    ├─ Karpenter Node IAM Role
    └─ Node Instance Profile
```

## IAM Role Alignment

This deployment ensures **strict alignment between Kubernetes service account permissions and AWS IAM roles** through the following design:

### Service Account to IAM Role Mapping

```
Kubernetes ServiceAccount (karpenter/karpenter)
              ↓ (IRSA via OIDC)
AWS IAM Role: {ClusterName}-karpenter-controller-role
              ↓
IAM Policies: EC2 Management, Pricing, PassRole
```

### EC2 Nodes to IAM Role Mapping

```
Karpenter EC2NodeClass (references instanceProfile)
              ↓
AWS IAM Instance Profile: {ClusterName}-karpenter-node-instance-profile
              ↓
AWS IAM Role: {ClusterName}-karpenter-node-role
              ↓
IAM Policies: EKS Worker Node, Container Registry, SSM, CNI
```

### Key Design Decisions

| Component | Value | Rationale |
|-----------|-------|-----------|
| **IRSA Method** | OIDC Federation | No AWS credentials required in pods; secure and audit-able |
| **Instance Profile** | Named explicitly | Consistent across Terraform/CloudFormation/Kubernetes manifests |
| **Role Names** | Cluster-scoped (`{ClusterName}-*`) | Supports multi-cluster deployments; clear ownership |
| **Config Fetching** | Dynamic from CloudFormation | Always uses actual deployed values; prevents configuration drift |

### Role Validation

All IAM roles are automatically validated during deployment:
- ServiceAccount IRSA annotation matches CloudFormation output
- Instance Profile name consistency checked across all manifests
- Trust policies validated for OIDC provider

## Prerequisites

Before deploying Karpenter, ensure you have:

### AWS Setup
- ✅ An existing EKS cluster running
- ✅ AWS CLI v2 installed and configured
- ✅ IAM permissions to create IAM roles and CloudFormation stacks
- ✅ VPC subnets and security groups tagged with `karpenter.sh/discovery: <cluster-name>`

### Local Tools
- ✅ `kubectl` (v1.24+)
- ✅ `helm` (v3.9+)
- ✅ `aws-cli` (v2.x)
- ✅ `bash` (v4.0+)

### AWS Permissions Required
For the AWS account running this deployment:
- `cloudformation:*` - CloudFormation stack management
- `iam:CreateRole`, `iam:PutRolePolicy`, `iam:PassRole` - IAM role creation
- `eks:DescribeCluster` - EKS cluster information
- `ec2:*` - EC2 operations (Karpenter needs these)
- SQS permissions for interruption queue (if using interruption handling)

### EKS Cluster Requirements
Your EKS cluster must have:
- OIDC provider configured (for IRSA)
- VPC CNI plugin installed
- Security groups and subnets tagged appropriately

## Deployment Guide

### Step 1: Configure Deployment Parameters

Edit `config.env` with your environment-specific values:

```bash
# Open and edit the configuration file
vi config.env

# Key parameters to update:
# CLUSTER_NAME - Your EKS cluster name
# AWS_REGION - AWS region where your cluster runs
# AWS_ACCOUNT_ID - (Auto-populated from aws sts get-caller-identity)
# KARPENTER_VERSION - Version of Karpenter to install (default: 1.8.6)
# NODE_INSTANCE_TYPES - Comma-separated list of instance types
```

### Step 2: Pre-deployment Checks

Verify all prerequisites and configuration:

```bash
# Check AWS CLI access
aws sts get-caller-identity

# Verify cluster access
aws eks update-kubeconfig --region us-east-1 --name finishline-eks-cluster
kubectl get nodes

# Verify OIDC provider is configured
aws eks describe-cluster --name finishline-eks-cluster --region us-east-1 \
  --query 'cluster.identity.oidc.issuer' --output text
```

### Step 3: Tag VPC Resources

Karpenter uses tags to discover subnets and security groups. Tag your VPC resources:

```bash
# Tag subnets (from AWS console or CLI)
aws ec2 create-tags \
  --resources subnet-xxxxx \
  --tags Key=karpenter.sh/discovery,Value=finishline-eks-cluster \
  --region us-east-1

# Tag security groups
aws ec2 create-tags \
  --resources sg-xxxxx \
  --tags Key=karpenter.sh/discovery,Value=finishline-eks-cluster \
  --region us-east-1
```

### Step 4: Generate Manifests

Generate Kubernetes manifests based on your configuration:

```bash
cd scripts
bash generate-manifests.sh
cd ..
```

This creates:
- `manifests/ec2nodeclass.yaml` - EC2 node configuration
- `manifests/nodepool.yaml` - Karpenter NodePool configuration

### Step 5: Deploy Karpenter

Run the deployment script:

```bash
cd scripts
bash deploy.sh
cd ..
```

The script will:
1. ✅ Deploy CloudFormation stack (IAM roles)
2. ✅ Update kubeconfig
3. ✅ Install Karpenter CRDs
4. ✅ Create Karpenter service account with IRSA
5. ✅ Install Karpenter Helm chart
6. ✅ Apply EC2NodeClass and NodePool manifests
7. ✅ Verify the deployment

Expected output:
```
==========================================
Deploying Karpenter bootstrap resources...
==========================================
...
==========================================
Deployment completed successfully!
==========================================
Run './verify.sh' to check Karpenter status
```

### Step 6: Verify Installation

Check the Karpenter deployment:

```bash
cd scripts
bash verify.sh
cd ..
```

Expected results:
- Karpenter controller pod running in `karpenter` namespace
- EC2NodeClass created
- NodePool created
- Worker nodes available

## Configuration

### config.env Parameters

| Parameter | Description | Default | Notes |
|-----------|-------------|---------|-------|
| `CLUSTER_NAME` | EKS cluster name | `finishline-eks-cluster` | Used to construct IAM role names |
| `AWS_REGION` | AWS region | `us-east-1` | Must match cluster region |
| `AWS_ACCOUNT_ID` | AWS account ID | Auto-detected via `aws sts` | Override only if cross-account setup |
| `KARPENTER_VERSION` | Karpenter version | `1.8.6` | Check compatibility matrix |
| `KARPENTER_NAMESPACE` | Kubernetes namespace | `karpenter` | Standard convention; supported by Helm |
| `SERVICE_ACCOUNT_NAME` | K8s service account | `karpenter` | Must match IRSA annotation |
| `KARPENTER_CONTROLLER_ROLE` | **Dynamic** - fetched from CloudFormation | Auto-populated after CF deploy | Best practice: never hardcode |
| `NODE_INSTANCE_TYPES` | Comma-separated instance types | `t3.large,t3a.large,m5.large,m5a.large` | Include several types for flexibility |
| `CPU_LIMIT` | Max CPU for NodePool | `20` | Tune based on workload needs |
| `CAPACITY_TYPE` | Capacity type | `on-demand` | Use `spot` for dev/batch workloads |
| `AMI_FAMILY` | AMI family | `Bottlerocket` | Alternative: `AL2` (Amazon Linux 2) |
| `STACK_NAME` | CloudFormation stack | `karpenter-{CLUSTER_NAME}` | Auto-generated; modify with caution |

**Important:** The `KARPENTER_CONTROLLER_ROLE` is now **dynamically fetched** from CloudFormation outputs after the stack is deployed. This ensures the deployment always uses the actual IAM role ARN that was created, preventing configuration drift.

### CloudFormation Template (`cloudformation/karpenter-bootstrap.yaml`)

Creates three linked IAM resources:

#### 1. KarpenterControllerRole
- **Type:** IAM Role with IRSA assume policy
- **Trust:** OIDC provider + ServiceAccount condition
- **Policies:**
  - `EC2Management` - CreateLaunchTemplate, CreateFleet, RunInstances, TerminateInstances, DeleteLaunchTemplate, CreateTags, DeleteTags
  - `Pricing` - GetProducts (for price-aware scheduling)
  - `PassNodeRole` - Can pass KarpenterNodeRole to EC2 instances
  - `EKSDescribe` - Read EKS cluster information

#### 2. KarpenterNodeRole
- **Type:** IAM Role for EC2 instances
- **Trust:** EC2 service principal
- **Managed Policies:**
  - `AmazonEKSWorkerNodePolicy` - Core EKS node permissions
  - `AmazonEC2ContainerRegistryReadOnly` - ECR access for container images
  - `AmazonSSMManagedInstanceCore` - AWS Systems Manager access
  - `AmazonEKS_CNI_Policy` - VPC CNI plugin permissions

#### 3. KarpenterNodeInstanceProfile
- **Type:** IAM Instance Profile
- **Explicit Name:** `{ClusterName}-karpenter-node-instance-profile`
- **Associates:** KarpenterNodeRole
- **Purpose:** Links the IAM role to EC2 instances created by Karpenter

**Critical:** All IAM resource names are constructed using `!Sub "${ClusterName}-*"` to support multi-cluster scenarios and enable clear resource ownership.

## Troubleshooting

### Issue: ServiceAccount IRSA role not working

```bash
# Check ServiceAccount has correct annotation
kubectl get sa -n karpenter karpenter -o yaml | grep role-arn

# Expected format:
# eks.amazonaws.com/role-arn: arn:aws:iam::ACCOUNT_ID:role/{ClusterName}-karpenter-controller-role

# Verify the role exists
aws iam get-role --role-name {ClusterName}-karpenter-controller-role

# Check IAM role trust relationship includes OIDC provider
aws iam get-role --role-name {ClusterName}-karpenter-controller-role \
  --query 'Role.AssumeRolePolicyDocument' | jq .

# Should include your OIDC provider URL and service account condition
```

### Issue: Instance Profile mismatch (nodes fail to provision)

```bash
# Verify instance profile exists
aws iam get-instance-profile --instance-profile-name {ClusterName}-karpenter-node-instance-profile

# Check EC2NodeClass references correct instance profile
kubectl get ec2nodeclass default -o yaml | grep -i instanceProfile

# Verify instance profile contains correct role
aws iam get-instance-profile --instance-profile-name {ClusterName}-karpenter-node-instance-profile \
  --query 'InstanceProfile.Roles[0].RoleName'

# Should output: {ClusterName}-karpenter-node-role
```

### Issue: IRSA role ARN mismatch after CloudFormation delete/recreate

```bash
# Re-source config.env to fetch updated role ARN
source config.env

# Echo to verify new ARN
echo $KARPENTER_CONTROLLER_ROLE

# Update ServiceAccount if needed
kubectl patch serviceaccount karpenter -n karpenter \
  -p "{\"metadata\":{\"annotations\":{\"eks.amazonaws.com/role-arn\":\"${KARPENTER_CONTROLLER_ROLE}\"}}}"
```

### Issue: Cannot reach cluster

```bash
# Solution: Update kubeconfig
aws eks update-kubeconfig --region us-east-1 --name finishline-eks-cluster

# Verify access
kubectl get nodes
```

### Issue: "OIDC provider not found"

```bash
# Check OIDC provider setup
aws eks describe-cluster --name finishline-eks-cluster \
  --query 'cluster.identity.oidc.issuer' --output text

# Should return: https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLEID
```

### Issue: "Karpenter controller pod not running"

```bash
# Check pod status
kubectl get pods -n karpenter

# View logs
kubectl logs -n karpenter deployment/karpenter --tail=50

# Check for image pull errors
kubectl describe pod -n karpenter -l app.kubernetes.io/name=karpenter
```

### Issue: "Nodes not being provisioned"

```bash
# Check NodePool and EC2NodeClass
kubectl get nodepool
kubectl get ec2nodeclass

# Check resource requirements
kubectl describe nodepool default
kubectl describe ec2nodeclass default

# Check subnet/security group tags
aws ec2 describe-subnets --filters Name=tag:karpenter.sh/discovery,Values=finishline-eks-cluster
```

### Issue: "ServiceAccount IRSA role not working"

```bash
# Check ServiceAccount annotation
kubectl get sa -n karpenter karpenter -o jsonpath='{.metadata.annotations}'

# Verify role ARN is correct
kubectl get sa -n karpenter karpenter -o yaml | grep role-arn

# Check IAM role trust relationship
aws iam get-role --role-name finishline-eks-cluster-karpenter-controller-role \
  --query 'Role.AssumeRolePolicyDocument'
```

### Issue: "CloudFormation stack creation fails"

```bash
# Check stack events
aws cloudformation describe-stack-events \
  --stack-name Karpenter-finishline-eks-cluster --region us-east-1

# View stack status
aws cloudformation describe-stacks \
  --stack-name Karpenter-finishline-eks-cluster --region us-east-1

# Delete and retry if stuck
aws cloudformation delete-stack \
  --stack-name Karpenter-finishline-eks-cluster --region us-east-1
```

## Testing (Optional)

Deploy a test workload to verify Karpenter scaling:

```bash
# Deploy the inflate test workload
kubectl apply -f manifests/inflate.yaml

# Monitor scaling
watch 'kubectl get nodes -o wide'
watch 'kubectl get pods -l app=inflate'

# Clean up
kubectl delete -f manifests/inflate.yaml
```

## Cleanup

### Full Cleanup (Karpenter + IAM Roles)

```bash
cd scripts
bash cleanup.sh
cd ..
```

This removes:
- Test workload (inflate)
- Karpenter manifests (EC2NodeClass, NodePool)
- Karpenter Helm releases
- CloudFormation stack (IAM roles)

### Partial Cleanup

```bash
# Remove only Karpenter manifests
kubectl delete -f manifests/ec2nodeclass.yaml
kubectl delete -f manifests/nodepool.yaml

# Remove only Karpenter release (keep IAM roles)
helm uninstall karpenter -n karpenter
helm uninstall karpenter-crd -n karpenter
```

## Best Practices

### IAM & Security
1. **Never hardcode IAM role ARNs** - Use dynamic fetching from CloudFormation outputs (as implemented)
2. **IRSA over pod credentials** - ServiceAccount annotations leverage OIDC federation; no credentials in pods
3. **Explicit instance profile names** - Avoid auto-generated names that can cause drift
4. **Multi-cluster support** - Use cluster-scoped role names (`{ClusterName}-*`) for scalability
5. **Least privilege policies** - Review and restrict IAM permissions; don't use wildcards

### Deployment & Operations
6. **Tag your VPC resources** - Use tags to control subnet and security group discovery (required)
7. **Start with conservative limits** - Use small `CPU_LIMIT` initially; increase based on monitoring
8. **Monitor CloudFormation drift** - Verify IAM roles haven't been manually modified
9. **Store configs in Git** - Version control `config.env` for repeatability
10. **Automate verification** - Run `verify.sh` after each deployment

### Performance & Cost
11. **Mix capacity types** - Combine on-demand and Spot instances for cost optimization
12. **Configure node consolidation** - Enable disruption policies to bin-pack efficiently
13. **Set pod resource requests** - Karpenter scheduling depends on accurate resource requests
14. **Monitor metrics** - Track node utilization, provisioning time, and cost
15. **Use Bottlerocket** - Faster boot, smaller footprint, better security posture

### Troubleshooting
16. **Check logs first** - `kubectl logs -n karpenter deployment/karpenter`
17. **Validate manifests before applying** - Use `kubectl apply --dry-run=client`
18. **Cross-check IAM** - When nodes don't provision, always verify IAM roles and trust policies
19. **Review subnet tags** - Nodes won't provision without proper tag discovery
20. **Test in dev cluster** - Validate approach before production deployment

## Security Considerations

- ✅ IRSA (IAM Roles for Service Accounts) - No AWS credentials in pods
- ✅ Minimum IAM permissions - CloudFormation uses least-privilege policy
- ✅ EC2 metadata protection - HTTPTokens required (IMDSv2)
- ✅ Encrypted EBS volumes - Node volumes encrypted by default
- ✅ Security group tags - Control instance network access via tags
- ✅ **Role alignment** - Kubernetes ServiceAccounts properly mapped to AWS IAM roles
- ✅ **Drift prevention** - Dynamic config fetching from CloudFormation eliminates manual errors

## Recent Enhancements (v2.0)

### Role Alignment Improvements
This version includes comprehensive IAM role alignment to ensure ServiceAccount permissions always match EC2 node permissions:

**What Changed:**
1. **Dynamic Role ARN Fetching** - `config.env` now queries CloudFormation outputs instead of relying on hardcoded values
2. **Explicit Instance Profile Naming** - Instance profile names are now predictable and consistent across all components
3. **Kubernetes Manifest Consistency** - EC2NodeClass properly references instance profile matching CloudFormation output
4. **IRSA Validation** - Deployment scripts validate IRSA setup before proceeding

**Benefits:**
- ✅ Prevents configuration drift between Kubernetes and AWS IAM
- ✅ Supports safe re-deployments and role updates
- ✅ Enables multi-cluster scenarios with clear resource naming
- ✅ Facilitates audit and compliance checks

**Migration Notes:**
If upgrading from v1.x:
- Re-run `source config.env` to fetch new role ARNs
- Existing clusters continue to function with automatic updates
- No manual IAM modifications required

## Support and Resources

- [Karpenter Official Docs](https://karpenter.sh/)
- [Karpenter GitHub](https://github.com/aws/karpenter)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Karpenter on EKS Workshop](https://www.eksworkshop.com/)
- [AWS IRSA Documentation](https://docs.aws.amazon.com/eks/latest/userguide/iam-roles-for-service-accounts.html)

## File Structure

```
finishline-karpenter/
├── README.md                          # This file
├── QUICK_REFERENCE.md                 # Quick start guide
├── DEPLOYMENT_GUIDE.md                # Detailed deployment steps
├── AUDIT_SUMMARY.md                   # Compliance and audit info
├── config.env                         # Configuration (externalized)
│
├── cloudformation/
│   └── karpenter-bootstrap.yaml       # IAM roles and instance profiles
│
├── helm/
│   ├── install-karpenter.sh           # Helm installation script
│   └── serviceaccount.yaml            # K8s ServiceAccount with IRSA
│
├── manifests/
│   ├── ec2nodeclass.yaml              # EC2 node configuration
│   ├── nodepool.yaml                  # Karpenter NodePool definition
│   └── inflate.yaml                   # Test workload
│
└── scripts/
    ├── deploy.sh                      # Main deployment orchestrator
    ├── generate-manifests.sh          # Generate manifests from config
    ├── cleanup.sh                     # Full cleanup script
    ├── preflight-check.sh             # Pre-deployment validation
    └── verify.sh                      # Post-deployment verification
```

## Deployment Workflow

```
1. configure (config.env)              # Set environment variables
   ↓
2. preflight-check.sh                  # Validate prerequisites
   ↓
3. deploy.sh                           # Deploy CloudFormation + Karpenter
   ├── CloudFormation stack (IAM roles)
   ├── Create karpenter namespace
   ├── Install CRDs
   ├── Apply ServiceAccount (IRSA)
   ├── Install Helm chart
   └── Apply EC2NodeClass + NodePool
   ↓
4. verify.sh                           # Verify deployment succeeded
```

## License

This deployment template is provided as-is for use with AWS EKS clusters.

---

**Version:** 2.0 (Enhanced IAM Role Alignment)  
**Last Updated:** April 2026  
**Karpenter Version:** 1.8.6+  
**Status:** Production Ready ✅  
**Key Feature:** IRSA + Role Alignment Validation
![
  
](image-1.png)