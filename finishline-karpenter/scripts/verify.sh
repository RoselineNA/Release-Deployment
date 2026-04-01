#!/bin/bash
set -euo pipefail

echo "=========================================="
echo "Karpenter Verification"
echo "=========================================="

echo
echo "--- Karpenter Controller Pods ---"
kubectl get pods -n kube-system | grep karpenter || true

echo
echo "--- EC2NodeClass ---"
kubectl get ec2nodeclass

echo
echo "--- NodePools ---"
kubectl get nodepool

echo
echo "--- NodeClaims ---"
kubectl get nodeclaim || true

echo
echo "--- Worker Nodes ---"
kubectl get nodes -o wide || true

echo
echo "--- Instance Type Labels ---"
kubectl get nodes -L node.kubernetes.io/instance-type

echo
echo "--- Node OS / Bottlerocket Proof ---"
kubectl get nodes -o wide

echo
echo "--- Inflate Workload ---"
kubectl get deploy inflate || true
kubectl get pods -l app=inflate -o wide || true

echo
echo "--- Pending Pods ---"
kubectl get pods -A --field-selector=status.phase=Pending || true

echo
echo "--- Karpenter Logs (last 50 lines) ---"
kubectl logs -n kube-system deployment/karpenter --tail=50 || true

echo
echo "Verification completed."