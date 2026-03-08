#!/usr/bin/env bash
# Smoke test para sync-comms-metrics
# Uso: SUPABASE_URL=... SYNC_COMMS_METRICS_SECRET=... ./scripts/smoke-sync-comms.sh

set -euo pipefail
test -n "${SUPABASE_URL:-}" || { echo "Missing SUPABASE_URL"; exit 1; }
test -n "${SYNC_COMMS_METRICS_SECRET:-}" || { echo "Missing SYNC_COMMS_METRICS_SECRET"; exit 1; }

URL="${SUPABASE_URL%/}/functions/v1/sync-comms-metrics"
echo "Calling: $URL (dry_run=true)"
HTTP=$(curl -sS -o /tmp/comms_smoke.json -w "%{http_code}" \
  -X POST "$URL" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $SYNC_COMMS_METRICS_SECRET" \
  -H "x-sync-secret: $SYNC_COMMS_METRICS_SECRET" \
  -d '{"dry_run":true,"triggered_by":"smoke_script","rows":[]}')

echo "HTTP: $HTTP"
cat /tmp/comms_smoke.json | head -20
if [ "$HTTP" -lt 200 ] || [ "$HTTP" -ge 300 ]; then
  echo "Smoke failed"
  exit 1
fi
echo "Smoke passed"
