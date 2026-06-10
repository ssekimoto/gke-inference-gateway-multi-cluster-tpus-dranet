#!/bin/bash
set -euo pipefail

: "${CTX_ASIA:?Set CTX_ASIA before running this script.}"

echo -e "\n=== Creating Cross-Regional Gateway Resources ==="
kubectl apply -f config-cluster.yaml --context="$CTX_ASIA"

echo -e "\n=== Provisioning Global Load Balancer (This takes 5-10 minutes) ==="
echo "Working on the Gateway... waiting for Google Cloud to assign IPs and program routes..."

kubectl wait --for=condition=programmed gateway/cross-region-gateway --timeout=10m --context="$CTX_ASIA"

echo -e "\n=== SUCCESS: Gateway is fully provisioned and ready! ==="
