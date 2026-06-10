#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"

declare -A TPU_ZONES=(
  ["europe-west4"]="europe-west4-a"
  ["asia-northeast1"]="asia-northeast1-b"
)

membership_exists() {
  local membership="$1"
  local location="$2"

  gcloud container fleet memberships describe "$membership" \
    --location="$location" \
    --project="$PROJECT_ID" \
    >/dev/null 2>&1
}

wait_for_regional_membership() {
  local cluster="$1"
  local region="$2"

  echo "Waiting for regional Fleet membership ${cluster} in ${region}..."
  for _ in {1..30}; do
    if membership_exists "$cluster" "$region"; then
      gcloud container fleet memberships describe "$cluster" \
        --location="$region" \
        --project="$PROJECT_ID" \
        --format="table(name,externalId,state.code,state.description)"
      return
    fi
    sleep 10
  done

  echo "ERROR: Regional Fleet membership ${cluster} was not created in ${region}."
  exit 1
}

for REGION in europe-west4 asia-northeast1; do
  ZONE="${TPU_ZONES[$REGION]}"
  CLUSTER="gke-${REGION}"

  echo "Ensuring ${CLUSTER} uses a regional Fleet membership in ${REGION}..."
  gcloud container clusters get-credentials "$CLUSTER" \
    --location="$ZONE" \
    --project="$PROJECT_ID"

  if membership_exists "$CLUSTER" global && ! membership_exists "$CLUSTER" "$REGION"; then
    echo "Found legacy global Fleet membership for ${CLUSTER}; moving it to ${REGION}..."
    gcloud container fleet ingress disable \
      --project="$PROJECT_ID" \
      --quiet || true
    gcloud container fleet memberships unregister "$CLUSTER" \
      --location=global \
      --gke-cluster="${ZONE}/${CLUSTER}" \
      --uninstall-connect-agent \
      --project="$PROJECT_ID" \
      --quiet
  fi

  gcloud container fleet memberships register "$CLUSTER" \
    --location="$REGION" \
    --gke-cluster="${ZONE}/${CLUSTER}" \
    --enable-workload-identity \
    --project="$PROJECT_ID" \
    --quiet

  wait_for_regional_membership "$CLUSTER" "$REGION"
done

echo "Fleet memberships are registered in their cluster regions."
