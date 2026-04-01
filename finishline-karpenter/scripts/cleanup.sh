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
# Cleanup
########################################################
echo "=========================================="
echo "Removing test workload..."
echo "=========================================="

kubectl delete -f ../manifests/inflate.yaml --ignore-not-found=true

echo "=========================================="
echo "Removing Karpenter manifests..."
echo "=========================================="

kubectl delete -f ../manifests/nodepool.yaml --ignore-not-found=true
kubectl delete -f ../manifests/ec2nodeclass.yaml --ignore-not-found=true

echo "=========================================="
echo "Removing Karpenter Helm releases..."
echo "=========================================="

helm uninstall karpenter -n "${KARPENTER_NAMESPACE}" || true
helm uninstall karpenter-crd -n "${KARPENTER_NAMESPACE}" || true

echo "=========================================="
echo "Removing Karpenter ServiceAccount..."
echo "=========================================="

kubectl delete -f ../helm/serviceaccount.yaml --ignore-not-found=true

echo "=========================================="
echo "Deleting CloudFormation stack..."
echo "=========================================="

aws cloudformation delete-stack \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" || {
  echo "Warning: Failed to delete CloudFormation stack. Check AWS console."
}

# Wait for stack deletion
echo "Waiting for stack deletion (this may take several minutes)..."
aws cloudformation wait stack-delete-complete \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" 2>/dev/null || echo "Note: Stack deletion monitoring completed or stack already deleted"

echo "=========================================="
echo "Cleanup completed."
echo "=========================================="