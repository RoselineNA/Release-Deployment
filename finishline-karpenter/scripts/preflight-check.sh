#!/bin/bash
set -euo pipefail

# Pre-flight checks before Karpenter deployment

echo "=========================================="
echo "Karpenter Pre-flight Checks"
echo "=========================================="

# Load configuration
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Configuration file not found at ${CONFIG_FILE}"
  exit 1
fi
source "${CONFIG_FILE}"

FAILED=0

########################################################
# Check required tools
########################################################
echo ""
echo "--- Checking required tools ---"

for tool in aws kubectl helm; do
  if command -v "${tool}" &> /dev/null; then
    VERSION=$(${tool} version 2>&1 | head -n 1 || echo "installed")
    echo "✓ ${tool}: ${VERSION}"
  else
    echo "✗ ${tool}: NOT INSTALLED"
    FAILED=$((FAILED + 1))
  fi
done

########################################################
# Check AWS credentials
########################################################
echo ""
echo "--- Checking AWS credentials ---"

if aws sts get-caller-identity &> /dev/null; then
  ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
  echo "✓ AWS credentials valid"
  echo "  Account: ${ACCOUNT}"
else
  echo "✗ AWS credentials not configured"
  FAILED=$((FAILED + 1))
fi

########################################################
# Check cluster access
########################################################
echo ""
echo "--- Checking cluster access ---"

if aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" &> /dev/null; then
  echo "✓ EKS cluster exists: ${CLUSTER_NAME}"
else
  echo "✗ EKS cluster not found: ${CLUSTER_NAME}"
  FAILED=$((FAILED + 1))
fi

if kubectl get nodes &> /dev/null; then
  NODE_COUNT=$(kubectl get nodes --no-headers | wc -l)
  echo "✓ Kubernetes cluster accessible (${NODE_COUNT} nodes)"
else
  echo "✗ Cannot access Kubernetes cluster"
  FAILED=$((FAILED + 1))
fi

########################################################
# Check OIDC provider
########################################################
echo ""
echo "--- Checking OIDC provider ---"

OIDC_URL=$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query 'cluster.identity.oidc.issuer' \
  --output text 2>/dev/null)

if [[ -n "${OIDC_URL}" && "${OIDC_URL}" != "None" && "${OIDC_URL}" != "null" ]]; then
  echo "✓ OIDC provider configured: ${OIDC_URL}"
else
  echo "✗ OIDC provider not configured for cluster"
  FAILED=$((FAILED + 1))
fi

########################################################
# Check VPC tagging
########################################################
echo ""
echo "--- Checking VPC tagging ---"

SUBNETS=$(aws ec2 describe-subnets \
  --filters "Name=tag:${DISCOVERY_TAG_KEY},Values=${DISCOVERY_TAG_VALUE}" \
  --region "${AWS_REGION}" \
  --query 'Subnets[*].SubnetId' \
  --output text 2>/dev/null)

if [[ -n "${SUBNETS}" ]]; then
  echo "✓ Subnets tagged for Karpenter discovery:"
  for subnet in ${SUBNETS}; do
    echo "  - ${subnet}"
  done
else
  echo "✗ No subnets tagged with ${DISCOVERY_TAG_KEY}=${DISCOVERY_TAG_VALUE}"
  echo "  Please tag your subnets before deploying:"
  echo "  aws ec2 create-tags --resources <subnet-id> \\"
  echo "    --tags Key=${DISCOVERY_TAG_KEY},Value=${DISCOVERY_TAG_VALUE} \\"
  echo "    --region ${AWS_REGION}"
  FAILED=$((FAILED + 1))
fi

SECURITY_GROUPS=$(aws ec2 describe-security-groups \
  --filters "Name=tag:${DISCOVERY_TAG_KEY},Values=${DISCOVERY_TAG_VALUE}" \
  --region "${AWS_REGION}" \
  --query 'SecurityGroups[*].GroupId' \
  --output text 2>/dev/null)

if [[ -n "${SECURITY_GROUPS}" ]]; then
  echo "✓ Security groups tagged for Karpenter discovery:"
  for sg in ${SECURITY_GROUPS}; do
    echo "  - ${sg}"
  done
else
  echo "✗ No security groups tagged with ${DISCOVERY_TAG_KEY}=${DISCOVERY_TAG_VALUE}"
  echo "  Please tag your security groups before deploying:"
  echo "  aws ec2 create-tags --resources <sg-id> \\"
  echo "    --tags Key=${DISCOVERY_TAG_KEY},Value=${DISCOVERY_TAG_VALUE} \\"
  echo "    --region ${AWS_REGION}"
  FAILED=$((FAILED + 1))
fi

########################################################
# Check IAM permissions
########################################################
echo ""
echo "--- Checking IAM permissions ---"

# Check if user can create IAM roles
if aws iam get-role --role-name "Karpenter-Test-Role-$$" &> /dev/null; then
  aws iam delete-role --role-name "Karpenter-Test-Role-$$" 2>/dev/null || true
fi

if aws iam create-role \
  --role-name "Karpenter-Test-Role-$$" \
  --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"ec2.amazonaws.com"},"Action":"sts:AssumeRole"}]}' &> /dev/null; then
  echo "✓ Can create IAM roles"
  aws iam delete-role --role-name "Karpenter-Test-Role-$$" 2>/dev/null || true
else
  echo "✗ Cannot create IAM roles (check permissions)"
  FAILED=$((FAILED + 1))
fi

########################################################
# Check configuration
########################################################
echo ""
echo "--- Configuration Summary ---"
echo "Cluster Name:        ${CLUSTER_NAME}"
echo "AWS Region:          ${AWS_REGION}"
echo "AWS Account ID:      ${AWS_ACCOUNT_ID}"
echo "Karpenter Version:   ${KARPENTER_VERSION}"
echo "Karpenter Namespace: ${KARPENTER_NAMESPACE}"
echo "Instance Types:      ${NODE_INSTANCE_TYPES}"
echo "CPU Limit:           ${CPU_LIMIT}"
echo "Capacity Type:       ${CAPACITY_TYPE}"

########################################################
# Summary
########################################################
echo ""
echo "=========================================="
if [[ ${FAILED} -eq 0 ]]; then
  echo "✓ All pre-flight checks passed!"
  echo "Ready to deploy Karpenter."
  echo ""
  echo "Next steps:"
  echo "  1. cd scripts"
  echo "  2. bash generate-manifests.sh"
  echo "  3. bash deploy.sh"
  exit 0
else
  echo "✗ Pre-flight checks failed (${FAILED} issue(s))"
  echo "Please resolve the issues above before deploying."
  exit 1
fi
