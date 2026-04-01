# Finishline Karpenter Deployment on AWS EKS

This repository contains a complete, production-ready infrastructure-as-code solution for deploying [Karpenter](https://karpenter.sh/) on AWS EKS clusters.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
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

✅ AWS CloudFormation templates for IAM role setup  
✅ Helm charts for Karpenter installation  
✅ Kubernetes manifests for EC2NodeClass and NodePool configuration  
✅ Automated deployment and cleanup scripts  
✅ Verification utilities  

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

| Parameter | Description | Default | Example |
|-----------|-------------|---------|---------|
| `CLUSTER_NAME` | EKS cluster name | `finishline-eks-cluster` | `my-cluster` |
| `AWS_REGION` | AWS region | `us-east-1` | `eu-west-1` |
| `AWS_ACCOUNT_ID` | AWS account ID | Auto-detected | `123456789012` |
| `KARPENTER_VERSION` | Karpenter version to install | `1.8.6` | `1.9.0` |
| `KARPENTER_NAMESPACE` | Kubernetes namespace | `karpenter` | `karpenter` |
| `NODE_INSTANCE_TYPES` | Comma-separated instance types | `t3.large,t3a.large,m5.large,m5a.large` | `t3.large,m5.large` |
| `CPU_LIMIT` | Max CPU for NodePool | `20` | `100` |
| `CAPACITY_TYPE` | Capacity type | `on-demand` | `spot` |
| `AMI_FAMILY` | AMI family | `Bottlerocket` | `AL2` |

### CloudFormation Template (`cloudformation/karpenter-bootstrap.yaml`)

Creates:

1. **KarpenterControllerRole**
   - IRSA role for Karpenter controller
   - Permissions to manage EC2 instances, launch templates, spot requests
   - Permissions to access EKS cluster endpoint

2. **KarpenterNodeRole**
   - IAM role for Karpenter-managed EC2 instances
   - AmazonEKSWorkerNodePolicy
   - AmazonEC2ContainerRegistryReadOnly
   - AmazonSSMManagedInstanceCore
   - AmazonEKS_CNI_Policy

3. **KarpenterNodeInstanceProfile**
   - Instance profile linking the node role to EC2 instances

## Troubleshooting

### Issue: "Cannot reach cluster"

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

1. **Tag your VPC resources** - Use tags to control subnet and security group discovery
2. **Start small** - Use conservative `CPU_LIMIT` values initially
3. **Monitor costs** - Karpenter can provision many nodes; set appropriate limits
4. **Review logs** - Check Karpenter logs regularly for provisioning issues
5. **Test in dev first** - Deploy to a test cluster before production
6. **Keep backups** - Store configuration in version control
7. **Update regularly** - Monitor Karpenter updates and upgrade versions
8. **Set pod limits** - Ensure your workloads have appropriate resource requests

## Security Considerations

- ✅ IRSA (IAM Roles for Service Accounts) - No AWS credentials in pods
- ✅ Minimum IAM permissions - CloudFormation uses least-privilege policy
- ✅ EC2 metadata protection - HTTPTokens required (IMDSv2)
- ✅ Encrypted EBS volumes - Node volumes encrypted by default
- ✅ Security group tags - Control instance network access via tags

## Support and Resources

- [Karpenter Official Docs](https://karpenter.sh/)
- [Karpenter GitHub](https://github.com/aws/karpenter)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)
- [Karpenter on EKS Workshop](https://www.eksworkshop.com/)

## License

This deployment template is provided as-is for use with AWS EKS clusters.

---

**Last Updated:** April 2026  
**Karpenter Version:** 1.8.6  
**Status:** Production Ready
