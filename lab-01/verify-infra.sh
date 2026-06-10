#!/bin/bash
set -euo pipefail

: "${PROJECT_ID:?Set PROJECT_ID before running this script.}"

echo -e "\n=== Verifying GKE Clusters ==="
gcloud container clusters list --filter="name:gke-europe-west4 OR name:gke-asia-northeast1" --project="$PROJECT_ID"

echo -e "\n=== Verifying VPC Network ==="
gcloud compute networks list --filter="name:tpu-gke-dranet-vpc" --project="$PROJECT_ID"

echo -e "\n=== Verifying Reserved Static IPs for Gateway ==="
gcloud compute addresses list --filter="name~qwen-gateway-ip" --project="$PROJECT_ID"

echo -e "\n=== Verifying GCS Bucket ==="
gcloud storage ls | grep "${PROJECT_ID}-qwen-weights"

echo -e "\n=== Verifying GCS FUSE Service Account ==="
gcloud iam service-accounts list --filter="email:gcs-fuse-sa@${PROJECT_ID}.iam.gserviceaccount.com" --project="$PROJECT_ID"
