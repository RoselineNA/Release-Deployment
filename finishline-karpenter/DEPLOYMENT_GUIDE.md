# Karpenter Deployment Guide

This guide provides step-by-step instructions for deploying Karpenter on AWS EKS.

## Quick Start

### Prerequisites
- AWS CLI v2 installed and configured
- kubectl installed
- helm v3.9+ installed
- Existing EKS cluster running
- OIDC provider enabled on cluster

### 5-Minute Deployment

```bash
# 1. Update configuration for your environment
nano config.env

# 2. Run pre-flight checks
cd scripts
bash preflight-check.sh

# 3. Generate manifests
bash generate-manifests.sh

# 4. Deploy Karpenter
bash deploy.sh

# 5. Verify installation
bash verify.sh
```

---

## Detailed Setup

### Step 1: Update Configuration

Edit `config.env` to match your AWS environment:

```bash
vi config.env
```

**Critical parameters:**

| Variable | Purpose | Update Required |
|----------|---------|-----------------|
| `CLUSTER_NAME` | EKS cluster name | **YES** |
| `AWS_REGION` | AWS region | **YES** |
| `AWS_ACCOUNT_ID` | Auto-detected | Usually NO |
| `KARPENTER_VERSION` | Version to install | Optional |
| `NODE_INSTANCE_TYPES` | EC2 instance types | Optional |

Example for `us-west-2` cluster named `my-cluster`:

```bash
export CLUSTER_NAME="my-cluster"
export AWS_REGION="us-west-2"
export KARPENTER_VERSION="1.8.6"
export NODE_INSTANCE_TYPES="t3.large,t3a.large,m5.large"
```

### Step 2: Tag VPC Resources

Karpenter discovers subnets and security groups using AWS tags. Your VPC resources must be tagged:

#### Tag Subnets

Using AWS Console:
1. Go to VPC > Subnets
2. Select your cluster's subnets
3. Add tag: `Key: karpenter.sh/discovery` | `Value: <cluster-name>`

Using AWS CLI:
```bash
# Tag subnets
aws ec2 create-tags \
  --resources subnet-12345678 subnet-87654321 \
  --tags Key=karpenter.sh/discovery,Value=finishline-eks-cluster \
  --region us-east-1

# Verify
aws ec2 describe-subnets \
  --subnet-ids subnet-12345678 \
  --query 'Subnets[*].Tags'
```

#### Tag Security Groups

```bash
# Tag security group(s)
aws ec2 create-tags \
  --resources sg-12345678 \
  --tags Key=karpenter.sh/discovery,Value=finishline-eks-cluster \
  --region us-east-1

# Verify
aws ec2 describe-security-groups \
  --group-ids sg-12345678 \
  --query 'SecurityGroups[*].Tags'
```

### Step 3: Verify OIDC Provider

Karpenter uses IRSA (IAM Roles for Service Accounts), which requires OIDC:

```bash
# Check if OIDC is configured
aws eks describe-cluster \
  --name finishline-eks-cluster \
  --region us-east-1 \
  --query 'cluster.identity.oidc.issuer' \
  --output text

# Output should be: https://oidc.eks.us-east-1.amazonaws.com/id/EXAMPLEID
# If it's null or empty, enable OIDC (script available upon request)
```

### Step 4: Run Pre-flight Checks

This validates all prerequisites are met:

```bash
cd scripts
bash preflight-check.sh
```

Expected output:
```
==========================================
Karpenter Pre-flight Checks
==========================================

--- Checking required tools ---
✓ aws: aws-cli/2.13.0
✓ kubectl: v1.26.0
✓ helm: v3.12.0

--- Checking AWS credentials ---
✓ AWS credentials valid
  Account: 123456789012

--- Checking cluster access ---
✓ EKS cluster exists: finishline-eks-cluster
✓ Kubernetes cluster accessible (3 nodes)

--- Checking OIDC provider ---
✓ OIDC provider configured: https://oidc.eks.us-east-1.amazonaws.com/id/ABC123

--- Checking VPC tagging ---
✓ Subnets tagged for Karpenter discovery:
  - subnet-12345678
  - subnet-87654321
✓ Security groups tagged for Karpenter discovery:
  - sg-12345678

--- Checking IAM permissions ---
✓ Can create IAM roles

☑ All pre-flight checks passed!
Ready to deploy Karpenter.
```

If any checks fail, the script will show what needs to be fixed.

### Step 5: Generate Kubernetes Manifests

The manifests are generated dynamically from `config.env`:

```bash
bash generate-manifests.sh
```

This creates two files:
- `manifests/ec2nodeclass.yaml` - EC2 node template
- `manifests/nodepool.yaml` - Node pool configuration

Review generated manifests:
```bash
cat ../manifests/ec2nodeclass.yaml
cat ../manifests/nodepool.yaml
```

### Step 6: Deploy Karpenter

```bash
bash deploy.sh
```

Expected output:
```
==========================================
Deploying Karpenter bootstrap resources...
==========================================
Successfully created/updated stack named Karpenter-finishline-eks-cluster

==========================================
Installing Karpenter...
==========================================
...
Karpenter controller pod running
Karpenter installation completed successfully.

==========================================
Applying EC2NodeClass and NodePool...
==========================================
ec2nodeclass.bottlerocket created
nodepool.default created

==========================================
Verification...
==========================================
...

==========================================
Deployment completed successfully!
==========================================
Run './verify.sh' to check Karpenter status
```

### Step 7: Verify Deployment

```bash
bash verify.sh
```

Expected results:
```
=========================================="
Karpenter Verification
==========================================

--- Karpenter Controller Pods ---
NAME                             READY   STATUS    RESTARTS   AGE
karpenter-6dcf56f6fd-abc123       1/1     Running   0          2m

--- EC2NodeClass ---
NAME       AGE
default    1m

--- NodePools ---
NAME       AGE
default    1m

--- Worker Nodes ---
NAME                        STATUS   ROLES    AGE     VERSION           INSTANCE-TYPE
ip-10-0-1-100.ec2.internal   Ready    <none>   30s     v1.26.0           t3.large
ip-10-0-2-101.ec2.internal   Ready    <none>   40s     v1.26.0           m5.large

--- Karpenter Logs (last 50 lines) ---
INFO: provisioningcluster/controller scheduling 1 pod for consolidation
INFO: machine/cloudprovider launching 1 machine(s)
```

---

## Testing Karpenter

### Deploy Test Workload

This creates pods to test Karpenter's auto-scaling:

```bash
kubectl apply -f manifests/inflate.yaml

# Monitor node scaling
watch 'kubectl get nodes -o wide'

# Monitor pods
watch 'kubectl get pods -l app=inflate'

# After testing, clean up
kubectl delete -f manifests/inflate.yaml
```

---

## Scaling Configuration

### Adjust CPU Limits

Edit `config.env` and regenerate:

```bash
# Change limit from 20 to 50
sed -i 's/export CPU_LIMIT=.*/export CPU_LIMIT=50/' config.env

# Regenerate and apply
bash generate-manifests.sh
kubectl apply -f ../manifests/nodepool.yaml
```

### Change Instance Types

```bash
# Use different instance types
sed -i 's/export NODE_INSTANCE_TYPES=.*/export NODE_INSTANCE_TYPES="c5.large,c5a.large,r5.large"/' config.env

# Regenerate and apply
bash generate-manifests.sh
kubectl apply -f ../manifests/ec2nodeclass.yaml
```

### Add Spot Instances

```bash
# Edit config.env
sed -i 's/export CAPACITY_TYPE=.*/export CAPACITY_TYPE="spot"/' config.env

# Regenerate and apply
bash generate-manifests.sh
kubectl apply -f ../manifests/nodepool.yaml
```

---

## Troubleshooting

### Check Karpenter Logs

```bash
kubectl logs -n karpenter deployment/karpenter --tail=100
kubectl logs -n karpenter deployment/karpenter --follow
```

### Check Node Provisioning

```bash
# See provisioning attempts
kubectl get nodeclaims -o wide

# Describe failing nodeclaim
kubectl describe nodeclaim <name>
```

### Check IAM Permissions

```bash
# Verify ServiceAccount annotation
kubectl get sa -n karpenter karpenter -o yaml | grep role-arn

# Test assume role
aws sts assume-role-with-web-identity \
  --role-arn arn:aws:iam::ACCOUNT:role/finishline-eks-cluster-karpenter-controller-role \
  --role-session-name test \
  --web-identity-token $(kubectl -n karpenter create token karpenter)
```

### Debug VPC Tagging Issues

```bash
# List all tagged subnets
aws ec2 describe-subnets \
  --filters "Name=tag:karpenter.sh/discovery,Values=finishline-eks-cluster" \
  --region us-east-1

# List all tagged security groups
aws ec2 describe-security-groups \
  --filters "Name=tag:karpenter.sh/discovery,Values=finishline-eks-cluster" \
  --region us-east-1
```

---

## Uninstall / Cleanup

### Full Cleanup

Removes all Karpenter resources, including IAM roles:

```bash
cd scripts
bash cleanup.sh
cd ..
```

### Partial Cleanup

Remove only Karpenter components (keep IAM roles):

```bash
# Remove manifests
kubectl delete -f manifests/ec2nodeclass.yaml
kubectl delete -f manifests/nodepool.yaml

# Remove Helm releases
helm uninstall karpenter -n karpenter
helm uninstall karpenter-crd -n karpenter

# Manually delete CloudFormation stack if needed
aws cloudformation delete-stack \
  --stack-name Karpenter-finishline-eks-cluster \
  --region us-east-1
```

---

## Common Issues

### Issue: "Karpenter controller pod stuck in Pending"

**Symptoms:**
```
NAME      READY  STATUS   RESTARTS  AGE
karpenter-xxx   0/1    Pending  0        5m
```

**Solution:**
```bash
# Check pod constraints
kubectl describe pod -n karpenter -l app.kubernetes.io/name=karpenter

# Common causes:
# 1. Not enough resources - check node capacity
kubectl top nodes

# 2. SecurityGroup/Subnet not tagged - see "Troubleshooting VPC Tagging"

# 3. ServiceAccount IRSA not working - check role-arn annotation
kubectl get sa -n karpenter karpenter -o yaml
```

### Issue: "Nodes not being provisioned"

**Check:**
```bash
# 1. Is there pending work?
kubectl get pods --all-namespaces --field-selector=status.phase=Pending

# 2. Are consolidation policies preventing scaling?
kubectl describe nodepool default

# 3. Check Karpenter logs
kubectl logs -n karpenter deployment/karpenter | grep -i provision
```

### Issue: "CloudFormation stack creation fails"

**Check stack events:**
```bash
aws cloudformation describe-stack-events \
  --stack-name Karpenter-finishline-eks-cluster \
  --region us-east-1 \
  --query 'StackEvents[?ResourceStatus==`CREATE_FAILED`]'
```

**Common causes:**
- IAM role with same name already exists
- OIDC provider URL incorrect
- Stack name already exists

**Solution:**
```bash
# Delete failed stack
aws cloudformation delete-stack \
  --stack-name Karpenter-finishline-eks-cluster \
  --region us-east-1

# Wait for deletion
aws cloudformation wait stack-delete-complete \
  --stack-name Karpenter-finishline-eks-cluster \
  --region us-east-1

# Retry deployment
bash deploy.sh
```

---

## Next Steps

1. **Monitor Karpenter:** Set up CloudWatch alarms and dashboards
2. **Optimize costs:** Review and adjust instance types and limits
3. **Advanced config:** Explore Karpenter consolidation policies
4. **Helm values:** Customize Helm values in `install-karpenter.sh`

---

## Support

- [Karpenter Documentation](https://karpenter.sh/)
- [GitHub Issues](https://github.com/aws/karpenter/issues)
- [AWS EKS Best Practices](https://aws.github.io/aws-eks-best-practices/)

---

**Last Updated:** April 2026  
**Version:** 1.0.0
