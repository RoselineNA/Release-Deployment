#!/bin/bash
set -euo pipefail

# Load configuration
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Configuration file not found at ${CONFIG_FILE}"
  exit 1
fi
source "${CONFIG_FILE}"

echo "=========================================="
echo "Karpenter Verification"
echo "=========================================="

echo
echo "--- Karpenter Controller Pods ---"
kubectl get pods -n "${KARPENTER_NAMESPACE}" -l app.kubernetes.io/name=karpenter || true

echo
echo "--- EC2NodeClass ---"
kubectl get ec2nodeclass || true

echo
echo "--- NodePools ---"
kubectl get nodepool || true

echo
echo "--- NodeClaims ---"
kubectl get nodeclaim || true

echo
echo "--- Worker Nodes ---"
kubectl get nodes -o wide || true

echo
echo "--- Instance Type Labels ---"
kubectl get nodes -L node.kubernetes.io/instance-type || true

echo
echo "--- Node Image Info ---"
kubectl get nodes -o jsonpath='{.items[*].status.nodeInfo.osImage}' | tr ' ' '\n' | sort | uniq -c || true

echo
echo "--- Inflate Test Workload ---"
kubectl get deploy inflate -n default 2>/dev/null || echo "No inflate deployment found (expected if not deployed)"
kubectl get pods -l app=inflate -o wide 2>/dev/null || echo "No inflate pods found"

echo
echo "--- Pending Pods ---"
kubectl get pods -A --field-selector=status.phase=Pending || echo "No pending pods"

echo
echo "--- Karpenter Controller Logs (last 50 lines) ---"
kubectl logs -n "${KARPENTER_NAMESPACE}" deployment/karpenter --tail=50 2>/dev/null || echo "Could not fetch logs"

echo
echo "=========================================="
echo "Verification completed."
echo "=========================================="