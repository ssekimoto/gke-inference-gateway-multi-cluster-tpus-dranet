#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"
: "${CTX_EU:?Set CTX_EU before running this script.}"
: "${CTX_ASIA:?Set CTX_ASIA before running this script.}"

gcloud container clusters get-credentials gke-asia-northeast1 --zone asia-northeast1-b --project="$PROJECT_ID"

kubectl apply -f ksa.yaml --context="$CTX_EU"
kubectl apply -f ksa.yaml --context="$CTX_ASIA"
kubectl apply -f download-job.yaml --context="$CTX_ASIA"
