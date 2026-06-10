#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"

declare -A TPU_ZONES=(
  ["europe-west4"]="europe-west4-a"
  ["asia-northeast1"]="asia-northeast1-b"
)

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

  echo "Waiting for Connect agent on ${CLUSTER}..."
  kubectl rollout status deployment/gke-connect-agent \
    --namespace=gke-connect \
    --timeout=5m \
    --context="$CTX"
done

echo "Fleet memberships are registered and Connect agents are ready."
