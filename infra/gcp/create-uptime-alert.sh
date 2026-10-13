#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PAIRDESK_GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null || true)}
CHANNEL=${PAIRDESK_GCP_NOTIFICATION_CHANNEL:-}
MODE=${1:---plan}
CHECK_ID=pairdesk-api-and-livekit-readiness-YFrmeFR3gjo
POLICY_TITLE='PairDesk API and LiveKit readiness failure'

[[ "$MODE" == --plan || "$MODE" == --apply ]] || { echo 'Usage: create-uptime-alert.sh [--plan|--apply]' >&2; exit 2; }
[[ "$PROJECT" =~ ^[a-z][a-z0-9-]+$ ]] || { echo 'Set PAIRDESK_GCP_PROJECT to the GCP project ID.' >&2; exit 2; }
[[ -n "$CHANNEL" ]] || { echo 'Set PAIRDESK_GCP_NOTIFICATION_CHANNEL to an existing, verified Monitoring notification-channel ID.' >&2; exit 2; }

if [[ "$CHANNEL" == projects/* ]]; then
  [[ "$CHANNEL" == "projects/$PROJECT/notificationChannels/"* ]] || { echo 'Notification channel must belong to PAIRDESK_GCP_PROJECT.' >&2; exit 2; }
  CHANNEL_PATH=$CHANNEL
else
  [[ "$CHANNEL" =~ ^[A-Za-z0-9_-]+$ ]] || { echo 'Notification channel ID contains unsupported characters.' >&2; exit 2; }
  CHANNEL_PATH="projects/$PROJECT/notificationChannels/$CHANNEL"
fi

POLICY_FILE=$(mktemp)
trap 'rm -f "$POLICY_FILE"' EXIT
python3 - "$POLICY_FILE" "$PROJECT" "$CHANNEL_PATH" "$CHECK_ID" "$POLICY_TITLE" <<'PY'
import json
import sys

path, project, channel, check_id, title = sys.argv[1:]
policy = {
    "displayName": title,
    "documentation": {
        "mimeType": "text/markdown",
        "content": "PairDesk's public HTTPS uptime check also calls /readyz, which verifies the LiveKit media dependency. Check the PairDesk VM, API container, LiveKit container, TLS proxy, and Cloud Monitoring uptime-check history before restarting services.",
    },
    "combiner": "OR",
    "conditions": [{
        "displayName": "API and media readiness uptime check fails",
        "conditionThreshold": {
            "filter": (
                'metric.type="monitoring.googleapis.com/uptime_check/check_passed" '
                f'AND metric.label.check_id="{check_id}" '
                'AND resource.type="uptime_url"'
            ),
            "aggregations": [{
                "alignmentPeriod": "300s",
                "perSeriesAligner": "ALIGN_NEXT_OLDER",
                "crossSeriesReducer": "REDUCE_COUNT_FALSE",
                "groupByFields": ["resource.label.*"],
            }],
            "comparison": "COMPARISON_GT",
            "thresholdValue": 0,
            "duration": "300s",
            "trigger": {"count": 1},
        },
    }],
    "notificationChannels": [channel],
    "enabled": True,
    "alertStrategy": {"autoClose": "604800s"},
}
with open(path, "w", encoding="utf-8") as out:
    json.dump(policy, out, indent=2)
    out.write("\n")
PY

echo "Project: $PROJECT"
echo "Uptime check: $CHECK_ID"
echo "Notification channel: $CHANNEL_PATH"
echo "Alert: $POLICY_TITLE"
if [[ "$MODE" == --plan ]]; then
  echo 'Plan only. Add --apply to create the Cloud Monitoring alert policy.'
  exit 0
fi

EXISTING=$(gcloud monitoring policies list --project "$PROJECT" \
  --filter="displayName=\"$POLICY_TITLE\"" --format='value(name)' | head -n 1)
if [[ -n "$EXISTING" ]]; then
  echo "An alert policy with this title already exists: $EXISTING" >&2
  echo 'Inspect it in Cloud Monitoring before making changes; this script will not duplicate or overwrite it.' >&2
  exit 1
fi

gcloud monitoring policies create --project "$PROJECT" --policy-from-file="$POLICY_FILE"
