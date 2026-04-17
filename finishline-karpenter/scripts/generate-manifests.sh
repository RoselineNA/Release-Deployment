#!/bin/bash
set -euo pipefail

# Generate Kubernetes manifests from templates using config.env

CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/config.env"
if [[ ! -f "${CONFIG_FILE}" ]]; then
  echo "ERROR: Configuration file not found at ${CONFIG_FILE}"
  exit 1
fi
source "${CONFIG_FILE}"

MANIFESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/manifests"

echo "=========================================="
echo "Generating Kubernetes manifests..."
echo "=========================================="
echo "Cluster: ${CLUSTER_NAME}"
echo "Namespace: ${KARPENTER_NAMESPACE}"
echo "Instance Types: ${NODE_INSTANCE_TYPES}"

########################################################
# Generate EC2NodeClass
########################################################
echo "Generating EC2NodeClass..."
cat > "${MANIFESTS_DIR}/ec2nodeclass.yaml" <<EOF
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: ${AMI_FAMILY}

  instanceProfile: KarpenterNodeInstanceProfile

  subnetSelectorTerms:
    - tags:
        ${DISCOVERY_TAG_KEY}: ${DISCOVERY_TAG_VALUE}

  securityGroupSelectorTerms:
    - tags:
        ${DISCOVERY_TAG_KEY}: ${DISCOVERY_TAG_VALUE}

  tags:
    Name: ${CLUSTER_NAME}-karpenter-node
    ManagedBy: Karpenter
    ${DISCOVERY_TAG_KEY}: ${DISCOVERY_TAG_VALUE}

  blockDeviceMappings:
    - deviceName: /dev/xvda
      ebs:
        volumeSize: ${NODE_VOLUME_SIZE}Gi
        volumeType: ${NODE_VOLUME_TYPE}
        encrypted: true
        deleteOnTermination: true

  metadataOptions:
    httpEndpoint: enabled
    httpProtocolIPv6: disabled
    httpPutResponseHopLimit: 2
    httpTokens: required

  tags:
    WorkloadType: General
EOF

########################################################
# Generate NodePool
########################################################
echo "Generating NodePool..."

# Convert comma-separated instance types to YAML array
INSTANCE_TYPES_YAML=$(echo "${NODE_INSTANCE_TYPES}" | tr ',' '\n' | sed 's/^/            - /' | tr '\n' ' ')

cat > "${MANIFESTS_DIR}/nodepool.yaml" <<EOF
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    metadata:
      labels:
        workload-type: general
    spec:
      nodeClassRef:
        apiVersion: karpenter.k8s.aws/v1
        kind: EC2NodeClass
        name: default

      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]

        - key: kubernetes.io/os
          operator: In
          values: ["linux"]

        - key: karpenter.sh/capacity-type
          operator: In
          values: ["${CAPACITY_TYPE}"]

        - key: node.kubernetes.io/instance-type
          operator: In
          values:
${INSTANCE_TYPES_YAML}

        - key: karpenter.sh/weighted-priority
          operator: In
          values: ["100"]

  disruption:
    consolidationPolicy: WhenUnderutilized
    consolidateAfter: 30s
    expireAfter: 604800s
    budgets:
      - nodes: "10%"

  limits:
    cpu: ${CPU_LIMIT}
    memory: 1000Gi

  weight: 10
EOF

echo "=========================================="
echo "Manifests generated successfully"
echo "=========================================="
echo "Files created:"
echo "  - ${MANIFESTS_DIR}/ec2nodeclass.yaml"
echo "  - ${MANIFESTS_DIR}/nodepool.yaml"
echo ""
echo "Review and customize as needed, then run: ../scripts/deploy.sh"
