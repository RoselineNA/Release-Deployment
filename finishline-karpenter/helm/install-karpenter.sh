#!/bin/bash
set -euo pipefail

# Load configuration from parent directory
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Configuration file not found at ${CONFIG_FILE}"
  exit 1
fi
source "${CONFIG_FILE}"

########################################################
# Validate required tools
########################################################
echo "=========================================="
echo "Validating prerequisites..."
echo "=========================================="

for tool in aws kubectl helm; do
  if ! command -v "${tool}" &> /dev/null; then
    echo "ERROR: ${tool} not installed"
    exit 1
  fi
done

echo "AWS CLI: $(aws --version 2>&1 | head -n 1)"
echo "kubectl: $(kubectl version --client --short 2>/dev/null || echo 'installed')"
echo "Helm: $(helm version --short 2>/dev/null || echo 'installed')"

########################################################
# Update kubeconfig
########################################################
echo "=========================================="
echo "Updating kubeconfig..."
echo "=========================================="

aws eks update-kubeconfig \
  --region "${AWS_REGION}" \
  --name "${CLUSTER_NAME}" || {
  echo "ERROR: Failed to update kubeconfig"
  exit 1
}

########################################################
# Validate cluster access
########################################################
echo "=========================================="
echo "Checking cluster access..."
echo "=========================================="

kubectl get nodes -o wide || {
  echo "ERROR: Cannot access cluster"
  exit 1
}

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
  --output text) || {
  echo "ERROR: Failed to fetch cluster endpoint"
  exit 1
}

echo "Cluster Endpoint: ${CLUSTER_ENDPOINT}"

########################################################
# Create Karpenter namespace
########################################################
echo "=========================================="
echo "Creating Karpenter namespace..."
echo "=========================================="

kubectl create namespace "${KARPENTER_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - || {
  echo "ERROR: Failed to create namespace"
  exit 1
}

########################################################
# Install CRDs first
########################################################
echo "=========================================="
echo "Installing Karpenter CRDs (v${KARPENTER_VERSION})..."
echo "=========================================="

helm upgrade --install karpenter-crd oci://public.ecr.aws/karpenter/karpenter-crd \
  --version "${KARPENTER_VERSION}" \
  --namespace "${KARPENTER_NAMESPACE}" \
  --wait --timeout 10m || {
  echo "ERROR: Failed to install Karpenter CRDs"
  exit 1
}

echo "Karpenter CRDs installed successfully"

########################################################
# Apply IRSA ServiceAccount (Corrected)
########################################################
echo "=========================================="
echo "Applying Karpenter ServiceAccount with IRSA..."
echo "=========================================="

TEMP_SA=$(mktemp)

cat <<EOF > "${TEMP_SA}"
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ${SERVICE_ACCOUNT_NAME}
  namespace: ${KARPENTER_NAMESPACE}
  annotations:
    eks.amazonaws.com/role-arn: ${KARPENTER_CONTROLLER_ROLE}
EOF

kubectl apply -f "${TEMP_SA}" || {
  echo "ERROR: Failed to apply ServiceAccount"
  rm -f "${TEMP_SA}"
  exit 1
}
rm -f "${TEMP_SA}"

echo "ServiceAccount applied successfully"

########################################################
# Install Karpenter controller
########################################################
echo "=========================================="
echo "Installing Karpenter Controller (v${KARPENTER_VERSION})..."
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
  --wait --timeout 15m || {
  echo "ERROR: Failed to install Karpenter controller"
  exit 1
}

########################################################
# Verification
########################################################
echo "=========================================="
echo "Verifying Karpenter deployment..."
echo "=========================================="

kubectl rollout status deployment/karpenter -n "${KARPENTER_NAMESPACE}" --timeout=180s
kubectl get pods -n "${KARPENTER_NAMESPACE}" | grep karpenter || true

echo "=========================================="
echo "Karpenter installation completed successfully."
echo "=========================================="
