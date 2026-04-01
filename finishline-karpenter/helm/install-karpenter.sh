#!/bin/bash
set -euo pipefail

########################################################
# Configuration
########################################################
CLUSTER_NAME="finishline-eks-cluster"
AWS_REGION="us-east-1"
KARPENTER_VERSION="1.8.6"
KARPENTER_NAMESPACE="kube-system"
SERVICE_ACCOUNT_NAME="karpenter"
INTERRUPTION_QUEUE_NAME="${CLUSTER_NAME}-karpenter-interruption-queue"

########################################################
# Validate required tools
########################################################
echo "=========================================="
echo "Validating prerequisites..."
echo "=========================================="

command -v aws >/dev/null 2>&1 || { echo "ERROR: aws CLI not installed"; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "ERROR: kubectl not installed"; exit 1; }
command -v helm >/dev/null 2>&1 || { echo "ERROR: helm not installed"; exit 1; }

echo "AWS CLI: $(aws --version 2>&1 | head -n 1)"
echo "kubectl: $(kubectl version --client 2>/dev/null | head -n 1 || true)"
echo "Helm: $(helm version --short 2>/dev/null || true)"

########################################################
# Update kubeconfig
########################################################
echo "=========================================="
echo "Updating kubeconfig..."
echo "=========================================="

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}"

########################################################
# Validate cluster access
########################################################
echo "=========================================="
echo "Checking cluster access..."
echo "=========================================="

kubectl get nodes

########################################################
# Fetch cluster endpoint
########################################################
echo "=========================================="
echo "Fetching cluster endpoint..."
echo "=========================================="

CLUSTER_ENDPOINT=$(aws eks describe-cluster \
  --name "${CLUSTER_NAME}" \
  --region "${AWS_REGION}" \
  --query "cluster.endpoint" \
  --output text)

echo "Cluster Endpoint: ${CLUSTER_ENDPOINT}"

########################################################
# Install CRDs first
########################################################
echo "=========================================="
echo "Installing Karpenter CRDs..."
echo "=========================================="

helm upgrade --install karpenter-crd oci://public.ecr.aws/karpenter/karpenter-crd \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --create-namespace \
  --wait

########################################################
# Apply IRSA ServiceAccount
########################################################
echo "=========================================="
echo "Applying Karpenter ServiceAccount..."
echo "=========================================="

kubectl apply -f serviceaccount.yaml

########################################################
# Install Karpenter controller
########################################################
echo "=========================================="
echo "Installing Karpenter Controller..."
echo "=========================================="

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --set serviceAccount.create=false \
  --set serviceAccount.name="${SERVICE_ACCOUNT_NAME}" \
  --set settings.clusterName="${CLUSTER_NAME}" \
  --set settings.clusterEndpoint="${CLUSTER_ENDPOINT}" \
  --set settings.interruptionQueue="${INTERRUPTION_QUEUE_NAME}" \
  --set settings.isolatedVPC=true \
  --wait

########################################################
# Verify controller deployment
########################################################
echo "=========================================="
echo "Verifying Karpenter deployment..."
echo "=========================================="

kubectl rollout status deployment/karpenter -n "${KARPENTER_NAMESPACE}" --timeout=180s
kubectl get pods -n "${KARPENTER_NAMESPACE}" | grep karpenter || true

echo "=========================================="
echo "Karpenter installation completed successfully."
echo "=========================================="