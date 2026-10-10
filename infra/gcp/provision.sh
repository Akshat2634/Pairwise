#!/bin/bash
# Explicit provisioning plan for a new isolated PairDesk deployment.
set -euo pipefail
PROJECT=${PAIRDESK_GCP_PROJECT:?Set the approved GCP project}
REGION=${PAIRDESK_GCP_REGION:-us-central1}
ZONE=${PAIRDESK_GCP_ZONE:-us-central1-a}
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]+$ && "$REGION" =~ ^[a-z0-9-]+$ && "$ZONE" == "$REGION"-* ]] || { echo 'Invalid project, region or zone' >&2; exit 1; }
if [[ "${1:-}" != '--apply' ]]; then
  echo "Plan: project=$PROJECT region=$REGION zone=$ZONE"
  echo 'Create isolated pairdesk-vpc, pairdesk-subnet (10.70.0.0/24), static Premium IPv4,'
  echo 'pairdesk-server e2-standard-2, Ubuntu 24.04, 30 GiB balanced disk,'
  echo 'tagged media firewall and IAP-only SSH. No existing resources will be changed.'
  echo 'Estimated fixed cost about $60/month in us-central1 plus internet egress.'
  echo 'Run with --apply only after the project has been approved.'
  exit 0
fi
if gcloud compute networks describe pairdesk-vpc --project "$PROJECT" >/dev/null 2>&1; then
  echo 'pairdesk-vpc already exists; inspect prior provisioning rather than overwrite it' >&2
  exit 1
fi
gcloud compute networks create pairdesk-vpc --project "$PROJECT" --subnet-mode custom
gcloud compute networks subnets create pairdesk-subnet --project "$PROJECT" --network pairdesk-vpc \
  --region "$REGION" --range 10.70.0.0/24
gcloud compute firewall-rules create pairdesk-public-media --project "$PROJECT" --network pairdesk-vpc \
  --target-tags pairdesk-server --source-ranges 0.0.0.0/0 \
  --allow tcp:80,tcp:443,tcp:7881,udp:3478,udp:50000-50100
gcloud compute firewall-rules create pairdesk-iap-ssh --project "$PROJECT" --network pairdesk-vpc \
  --target-tags pairdesk-server --source-ranges 35.235.240.0/20 --allow tcp:22
gcloud compute addresses create pairdesk-ip --project "$PROJECT" --region "$REGION" --network-tier PREMIUM
ADDRESS=$(gcloud compute addresses describe pairdesk-ip --project "$PROJECT" --region "$REGION" --format='value(address)')
gcloud compute instances create pairdesk-server --project "$PROJECT" --zone "$ZONE" \
  --machine-type e2-standard-2 --network pairdesk-vpc --subnet pairdesk-subnet --address "$ADDRESS" \
  --network-tier PREMIUM --boot-disk-size 30GB --boot-disk-type pd-balanced \
  --image-family ubuntu-2404-lts-amd64 --image-project ubuntu-os-cloud \
  --tags pairdesk-server --no-service-account --no-scopes --shielded-secure-boot \
  --metadata enable-oslogin=TRUE
printf 'VM created with IP %s. Point API/media/TURN DNS here, then follow docs/rollout.md.\n' "$ADDRESS"
echo "SSH: gcloud compute ssh pairdesk-server --project $PROJECT --zone $ZONE --tunnel-through-iap"
echo 'IAP tunnel and OS Login IAM permissions are required for the operator.'
