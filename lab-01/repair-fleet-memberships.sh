#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"

declare -A TPU_ZONES=(
  ["europe-west4"]="europe-west4-a"
  ["asia-northeast1"]="asia-northeast1-b"
)

wait_for_connect_agent() {
  local cluster="$1"
  local ctx="$2"

  echo "Waiting for Connect agent namespace on ${cluster}..."
  for _ in {1..30}; do
    if kubectl get namespace gke-connect --context="$ctx" >/dev/null 2>&1; then
      break
    fi
    sleep 10
  done

  if ! kubectl get namespace gke-connect --context="$ctx" >/dev/null 2>&1; then
    echo "ERROR: gke-connect namespace was not created on ${cluster}."
    exit 1
  fi

  echo "Waiting for Connect agent pods on ${cluster}..."
  for _ in {1..30}; do
    if [[ -n "$(kubectl get pods --namespace=gke-connect --context="$ctx" --no-headers 2>/dev/null || true)" ]]; then
      kubectl get deployment,pod --namespace=gke-connect --context="$ctx"
      kubectl wait \
        --for=condition=Ready \
        pod \
        --all \
        --namespace=gke-connect \
        --timeout=5m \
        --context="$ctx"
      return
    fi
    sleep 10
  done

  echo "ERROR: Connect agent pods did not appear on ${cluster}."
  kubectl get all --namespace=gke-connect --context="$ctx" || true
  exit 1
}

for REGION in europe-west4 asia-northeast1; do
  ZONE="${TPU_ZONES[$REGION]}"
  CLUSTER="gke-${REGION}"
  CTX="gke_${PROJECT_ID}_${ZONE}_${CLUSTER}"

  echo "Registering ${CLUSTER} with Fleet and installing Connect agent..."
  gcloud container clusters get-credentials "$CLUSTER" \
    --location="$ZONE" \
    --project="$PROJECT_ID"

  gcloud container fleet memberships register "$CLUSTER" \
    --location=global \
    --gke-cluster="${ZONE}/${CLUSTER}" \
    --install-connect-agent \
    --enable-workload-identity \
    --project="$PROJECT_ID" \
    --quiet

  wait_for_connect_agent "$CLUSTER" "$CTX"
done

echo "Fleet memberships are registered and Connect agents are ready."
