#!/bin/bash
set -euo pipefail

########################################################
# Configuration
########################################################
CLUSTER_NAME="finishline-eks-cluster"
AWS_REGION="us-east-1"
STACK_NAME="Karpenter-${CLUSTER_NAME}"

echo "=========================================="
echo "Deploying Karpenter bootstrap resources..."
echo "=========================================="

aws cloudformation deploy \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}" \
  --template-file ../cloudformation/karpenter-bootstrap.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides ClusterName="${CLUSTER_NAME}"

echo "=========================================="
echo "Installing Karpenter..."
echo "=========================================="

pushd ../helm >/dev/null
bash install-karpenter.sh
popd >/dev/null

echo "=========================================="
echo "Applying EC2NodeClass and NodePool..."
echo "=========================================="

kubectl apply -f ../manifests/ec2nodeclass.yaml
kubectl apply -f ../manifests/nodepool.yaml

echo "=========================================="
echo "Deployment completed successfully."
echo "=========================================="