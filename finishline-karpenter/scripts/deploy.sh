#!/bin/bash
set -euo pipefail

# Load configuration
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Configuration file not found at ${CONFIG_FILE}"
  exit 1
fi
source "${CONFIG_FILE}"

########################################################
# Validation
########################################################
echo "=========================================="
echo "Validating deployment prerequisites..."
echo "=========================================="

if [[ -z "${CLUSTER_NAME}" ]] || [[ -z "${AWS_REGION}" ]] || [[ -z "${AWS_ACCOUNT_ID}" ]]; then
  echo "ERROR: Required configuration variables not set"
  exit 1
fi

echo "Cluster: ${CLUSTER_NAME}"
echo "Region: ${AWS_REGION}"
echo "Account ID: ${AWS_ACCOUNT_ID}"

########################################################
# Deploy CloudFormation
########################################################
echo "=========================================="
echo "Deploying Karpenter bootstrap resources..."
echo "=========================================="

aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --template-file ../cloudformation/karpenter-bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    ClusterName="${CLUSTER_NAME}" \
    OIDCProviderURL=$(aws eks describe-cluster --name "${CLUSTER_NAME}" --region "${AWS_REGION}" --query "cluster.identity.oidc.issuer" --output text | sed -e "s/^https:\/\///") || {
  echo "ERROR: CloudFormation deployment failed"
  exit 1
}

echo "CloudFormation stack deployed successfully"

########################################################
# Install Karpenter
########################################################
echo "=========================================="
echo "Installing Karpenter..."
echo "=========================================="

pushd ../helm >/dev/null
bash install-karpenter.sh || {
  echo "ERROR: Karpenter Helm installation failed"
  popd
  exit 1
}
popd >/dev/null

########################################################
# Apply Kubernetes manifests
########################################################
echo "=========================================="
echo "Applying EC2NodeClass and NodePool..."
echo "=========================================="

kubectl apply -f ../manifests/ec2nodeclass.yaml || {
  echo "ERROR: Failed to apply EC2NodeClass"
  exit 1
}

kubectl apply -f ../manifests/nodepool.yaml || {
  echo "ERROR: Failed to apply NodePool"
  exit 1
}

########################################################
# Verify deployment
########################################################
echo "=========================================="
echo "Verifying deployment..."
echo "=========================================="

# Wait for Karpenter controller to be ready
echo "Waiting for Karpenter controller to be ready..."
kubectl rollout status deployment/karpenter -n "${KARPENTER_NAMESPACE}" --timeout=5m || {
  echo "ERROR: Karpenter controller deployment did not become ready within 5 minutes"
  exit 1
}

echo "=========================================="
echo "Deployment completed successfully!"
echo "=========================================="
echo "Run './verify.sh' to check Karpenter status"