#!/bin/bash
set -euo pipefail

########################################################
# Configuration
########################################################
CLUSTER_NAME="finishline-eks-cluster"
AWS_REGION="us-east-1"
STACK_NAME="Karpenter-${CLUSTER_NAME}"

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

helm uninstall karpenter -n kube-system || true
helm uninstall karpenter-crd -n kube-system || true

echo "=========================================="
echo "Removing Karpenter ServiceAccount..."
echo "=========================================="

kubectl delete -f ../helm/serviceaccount.yaml --ignore-not-found=true

echo "=========================================="
echo "Deleting CloudFormation stack..."
echo "=========================================="

aws cloudformation delete-stack \
  --region "${AWS_REGION}" \
  --stack-name "${STACK_NAME}"

echo "=========================================="
echo "Cleanup initiated."
echo "=========================================="