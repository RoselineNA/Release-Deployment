git# Karpenter Quick Reference

## Before You Start
```bash
# 1. Configure your environment
nano config.env

# 2. Tag your VPC resources
aws ec2 create-tags --resources subnet-xxxxx --tags Key=karpenter.sh/discovery,Value=finishline-eks-cluster

# 3. Verify OIDC is enabled
aws eks describe-cluster --name finishline-eks-cluster --query 'cluster.identity.oidc.issuer'
```

## Deployment

```bash
# Full deployment (recommended)
cd scripts
bash preflight-check.sh    # ← Run this first!
bash generate-manifests.sh
bash deploy.sh
bash verify.sh

# Or run one command (if preflight passed)
cd scripts && bash preflight-check.sh && bash generate-manifests.sh && bash deploy.sh && bash verify.sh
```

## Monitoring

```bash
# Check Karpenter status
kubectl get pods -n karpenter

# View Karpenter logs
kubectl logs -n karpenter deployment/karpenter --tail=50

# Monitor node provisioning
kubectl get nodes -o wide
kubectl get nodeclaims

# Check resource consumption
kubectl top nodes
kubectl top pods -n karpenter
```

## Testing

```bash
# Deploy test workload
kubectl apply -f manifests/inflate.yaml

# Watch scaling
watch 'kubectl get nodes -L karpenter.sh/capacity-type'

# Clean up test
kubectl delete -f manifests/inflate.yaml
```

## Troubleshooting

```bash
# Check OIDC setup
aws eks describe-cluster --name finishline-eks-cluster \
  --query 'cluster.identity.oidc.issuer' --output text

# Verify ServiceAccount IRSA
kubectl get sa -n karpenter karpenter -o yaml | grep role-arn

# Check subnets are tagged
aws ec2 describe-subnets --filters \
  'Name=tag:karpenter.sh/discovery,Values=finishline-eks-cluster'

# View CloudFormation stack
aws cloudformation describe-stacks \
  --stack-name Karpenter-finishline-eks-cluster

# Check IAM role permissions
aws iam get-role-policy --role-name finishline-eks-cluster-karpenter-controller-role \
  --policy-name KarpenterControllerPolicy
```

## Configuration Changes

```bash
# Edit configuration
nano config.env

# Common changes:
sed -i 's/export CLUSTER_NAME=.*/export CLUSTER_NAME="new-cluster"/' config.env
sed -i 's/export AWS_REGION=.*/export AWS_REGION="eu-west-1"/' config.env
sed -i 's/export CPU_LIMIT=.*/export CPU_LIMIT=50/' config.env
sed -i 's/export CAPACITY_TYPE=.*/export CAPACITY_TYPE="spot"/' config.env

# Regenerate and apply
cd scripts
bash generate-manifests.sh
kubectl apply -f ../manifests/
```

## Cleanup

```bash
cd scripts

# Full cleanup (IAM + Karpenter)
bash cleanup.sh

# Partial cleanup (keep IAM roles)
kubectl delete -f ../manifests/
helm uninstall karpenter -n karpenter
helm uninstall karpenter-crd -n karpenter
```

## Common Issues

### Pods stuck in Pending
```bash
# Check what's preventing scheduling
kubectl describe pod <pod-name>

# Usually:
# - VPC not tagged (add tags with AWS console/CLI)
# - OIDC not working (check describe cluster output)
# - Resource limits hit (check CPU_LIMIT in config.env)
```

### CloudFormation creation fails
```bash
# Check stack events
aws cloudformation describe-stack-events \
  --stack-name Karpenter-finishline-eks-cluster | grep CREATE_FAILED

# Delete and retry
aws cloudformation delete-stack --stack-name Karpenter-finishline-eks-cluster
```

### Nodes not provisioning
```bash
# Check NodePool status
kubectl describe nodepool default

# Check for limits
kubectl describe nodepool default | grep -A5 "Limits:"

# Check logs
kubectl logs -n karpenter deployment/karpenter | grep -i provision
```

## Useful kubectl Commands

```bash
# Karpenter components
kubectl get pods -n karpenter
kubectl get ec2nodeclass
kubectl get nodepool
kubectl get nodeclaim

# Worker nodes
kubectl get nodes -o wide
kubectl get nodes -L node.kubernetes.io/instance-type
kubectl get nodes -L karpenter.sh/capacity-type

# All resources
kubectl get ec2nodeclass,nodepool,nodeclaim,nodes

# Describe resources
kubectl describe nodepool default
kubectl describe ec2nodeclass default
kubectl describe nodeclaim <name>
```

## Useful AWS CLI Commands

```bash
# Cluster info
aws eks describe-cluster --name finishline-eks-cluster
aws eks list-clusters

# OIDC provider
aws eks describe-cluster --name finishline-eks-cluster \
  --query 'cluster.identity.oidc.issuer'

# VPC tags
aws ec2 describe-subnets --filters Name=tag:karpenter.sh/discovery
aws ec2 describe-security-groups --filters Name=tag:karpenter.sh/discovery

# IAM roles
aws iam get-role --role-name finishline-eks-cluster-karpenter-controller-role
aws iam list-role-policies --role-name finishline-eks-cluster-karpenter-controller-role

# CloudFormation
aws cloudformation list-stacks --query "StackSummaries[?StackStatus!='DELETE_COMPLETE']"
aws cloudformation describe-stacks --stack-name Karpenter-finishline-eks-cluster
```

## Files Reference

| File | Purpose |
|------|---------|
| `README.md` | Full documentation |
| `DEPLOYMENT_GUIDE.md` | Step-by-step guide |
| `AUDIT_SUMMARY.md` | What was fixed |
| `config.env` | Configuration |
| `scripts/preflight-check.sh` | Validate prerequisites |
| `scripts/generate-manifests.sh` | Create manifests |
| `scripts/deploy.sh` | Deploy Karpenter |
| `scripts/verify.sh` | Check status |
| `scripts/cleanup.sh` | Remove everything |
| `cloudformation/karpenter-bootstrap.yaml` | IAM + CF stack |
| `helm/install-karpenter.sh` | Helm installation |
| `helm/serviceaccount.yaml` | Service account template |
| `manifests/ec2nodeclass.yaml` | Node template |
| `manifests/nodepool.yaml` | Node pool config |
| `manifests/inflate.yaml` | Test workload |

---

**Quick tips:**
- Always run `preflight-check.sh` first to catch issues early
- Use `config.env` to customize deployment - don't edit scripts
- Generate manifests after changing `config.env`
- Check logs with `kubectl logs -n karpenter deployment/karpenter -f`
- Tag VPC resources BEFORE running deploy script
- Keep a backup of your `config.env` file

**Deployment time:** ~10 minutes from start to ready
**Cleanup time:** ~5 minutes
