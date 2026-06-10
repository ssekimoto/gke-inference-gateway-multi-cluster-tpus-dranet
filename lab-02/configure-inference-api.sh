#!/bin/bash
set -euo pipefail

: "${CTX_EU:?Set CTX_EU before running this script.}"
: "${CTX_ASIA:?Set CTX_ASIA before running this script.}"

CRD_URL="https://raw.githubusercontent.com/kubernetes-sigs/gateway-api-inference-extension/v1.1.0/config/crd/bases/inference.networking.x-k8s.io_inferenceobjectives.yaml"

for CTX in $CTX_EU $CTX_ASIA; do
  kubectl apply -f "$CRD_URL" --context="$CTX"
  kubectl apply -f inference-objective.yaml --context="$CTX"
  kubectl apply -f metrics.yaml --context="$CTX"
done

helm upgrade --install qwen-pool \
  --kube-context "$CTX_EU" \
  --set inferencePool.modelServers.matchLabels.app=qwen-server \
  --set provider.name=gke \
  --version v1.1.0 \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool

helm upgrade --install qwen-pool \
  --kube-context "$CTX_ASIA" \
  --set inferencePool.modelServers.matchLabels.app=qwen-server \
  --set provider.name=gke \
  --set inferenceExtension.monitoring.gke.enabled=true \
  --version v1.1.0 \
  oci://registry.k8s.io/gateway-api-inference-extension/charts/inferencepool

for CTX in $CTX_EU $CTX_ASIA; do
  kubectl annotate inferencepool qwen-pool networking.gke.io/export="True" --overwrite --context="$CTX"
done

for CTX in $CTX_EU $CTX_ASIA; do
  echo "Verifying Inference API resources on $CTX..."
  kubectl get inferencepools --context="$CTX"
  kubectl get autoscalingmetrics tpu-cache --context="$CTX"
done
