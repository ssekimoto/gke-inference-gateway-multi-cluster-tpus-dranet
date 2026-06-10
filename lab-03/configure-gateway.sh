#!/bin/bash
set -euo pipefail

: "${CTX_ASIA:?Set CTX_ASIA before running this script.}"

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project)}"
GATEWAY_CLASS="gke-l7-cross-regional-internal-managed-mc"
CONFIG_MEMBERSHIP="projects/${PROJECT_ID}/locations/global/memberships/gke-asia-northeast1"

diagnose_gateway() {
  echo
  echo "=== Gateway diagnostics ==="
  kubectl get gateway cross-region-gateway --context="$CTX_ASIA" -o wide || true
  kubectl describe gateway cross-region-gateway --context="$CTX_ASIA" || true
  kubectl get gatewayclasses --context="$CTX_ASIA" || true
  gcloud container fleet ingress describe --project="$PROJECT_ID" || true
}

ensure_gateway_class() {
  if kubectl get gatewayclass "$GATEWAY_CLASS" --context="$CTX_ASIA" >/dev/null 2>&1; then
    return
  fi

  echo "GatewayClass $GATEWAY_CLASS is not present on the config cluster."
  echo "Re-enabling Fleet ingress for $CONFIG_MEMBERSHIP..."
  gcloud container fleet ingress disable --project="$PROJECT_ID" --quiet || true
  gcloud container fleet ingress enable \
    --config-membership="$CONFIG_MEMBERSHIP" \
    --project="$PROJECT_ID" \
    --quiet

  echo "Waiting for GatewayClass $GATEWAY_CLASS to appear..."
  for _ in {1..30}; do
    if kubectl get gatewayclass "$GATEWAY_CLASS" --context="$CTX_ASIA" >/dev/null 2>&1; then
      kubectl get gatewayclass "$GATEWAY_CLASS" --context="$CTX_ASIA"
      return
    fi
    sleep 10
  done

  echo "ERROR: GatewayClass $GATEWAY_CLASS did not appear after re-enabling Fleet ingress."
  diagnose_gateway
  exit 1
}

ensure_inference_pool_import() {
  if kubectl get gcpinferencepoolimports.networking.gke.io qwen-pool --context="$CTX_ASIA" >/dev/null 2>&1; then
    return
  fi

  echo "GCPInferencePoolImport qwen-pool is not present yet. Waiting for the export to sync..."
  for _ in {1..30}; do
    if kubectl get gcpinferencepoolimports.networking.gke.io qwen-pool --context="$CTX_ASIA" >/dev/null 2>&1; then
      kubectl get gcpinferencepoolimports.networking.gke.io qwen-pool --context="$CTX_ASIA"
      return
    fi
    sleep 10
  done

  echo "ERROR: GCPInferencePoolImport qwen-pool was not found on the config cluster."
  echo "Run ../lab-02/configure-inference-api.sh before configuring the Gateway, then retry this script."
  exit 1
}

ensure_gateway_class
ensure_inference_pool_import

echo -e "\n=== Creating Cross-Regional Gateway Resources ==="
kubectl apply -f config-cluster.yaml --context="$CTX_ASIA"

echo -e "\n=== Provisioning Global Load Balancer (This takes 5-10 minutes) ==="
echo "Working on the Gateway... waiting for Google Cloud to assign IPs and program routes..."

if ! kubectl wait --for=condition=programmed gateway/cross-region-gateway --timeout=10m --context="$CTX_ASIA"; then
  echo "ERROR: Gateway did not become programmed within 10 minutes."
  diagnose_gateway
  exit 1
fi

echo -e "\n=== SUCCESS: Gateway is fully provisioned and ready! ==="
