#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ENV_FILE="$ROOT/.env"
PID_FILE="$ROOT/runtime/worker.pid"
LOG_FILE="$ROOT/runtime/worker.log"

set -a
# shellcheck disable=SC1090
[[ -f "$ENV_FILE" ]] && source "$ENV_FILE"
set +a

echo "=== BKG BitTTS Worker ==="
echo "Koordinator: ${BITTTS_COORDINATOR_URL:-—}"
echo "Name:        ${BITTTS_WORKER_NAME:-—}"
if [[ -n "${BITTTS_SHUTUP_ROOT:-}" ]]; then
  echo "Bundle:      $BITTTS_SHUTUP_ROOT (lokal)"
elif [[ -d "$ROOT/runtime/bundle/scripts" ]]; then
  echo "Bundle:      $ROOT/runtime/bundle (Remote)"
else
  echo "Bundle:      noch nicht geladen"
fi
if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null; then
  echo "Status:      LÄUFT (PID $(cat "$PID_FILE"))"
else
  echo "Status:      GESTOPPT"
fi
[[ -f "$LOG_FILE" ]] && { echo ""; tail -n 20 "$LOG_FILE"; }
