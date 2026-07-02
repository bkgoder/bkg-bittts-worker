#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$ROOT/.env"
VENV_DIR="$ROOT/.venv"
RUNTIME_DIR="$ROOT/runtime"
PID_FILE="$RUNTIME_DIR/worker.pid"
LOG_FILE="$RUNTIME_DIR/worker.log"

resolve_worker_dataset() {
  local configured="${1:-}"
  local profile="${2:-mls-german}"
  if [[ -z "$configured" ]]; then printf '%s\n' "$ROOT/data/$profile"; return; fi
  if [[ "$configured" == /* || "$configured" == ./* ]]; then printf '%s\n' "$configured"; return; fi
  if [[ "$configured" == */* ]]; then printf '%s\n' "$ROOT/$configured"; return; fi
  printf '%s\n' "$ROOT/data/$configured"
}

[[ -x "$VENV_DIR/bin/python" ]] || { echo "Zuerst: bash scripts/linux/install.sh"; exit 1; }

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

export BITTTS_WORKER_RUNTIME="$RUNTIME_DIR"
export BITTTS_WORKER_DATASET
BITTTS_WORKER_DATASET="$(resolve_worker_dataset "${BITTTS_WORKER_DATASET:-}" "${BITTTS_DATASET_PROFILE:-mls-german}")"
mkdir -p "$BITTTS_WORKER_DATASET"

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ "$old_pid" =~ ^[0-9]+$ ]] && kill -0 "$old_pid" 2>/dev/null; then
    echo "Worker läuft bereits. PID: $old_pid"
    exit 0
  fi
  rm -f "$PID_FILE"
fi

: > "$LOG_FILE"
setsid "$VENV_DIR/bin/bkg-bittts-worker" >>"$LOG_FILE" 2>&1 &
pid=$!
printf '%s\n' "$pid" > "$PID_FILE"

for _ in $(seq 1 30); do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "Start fehlgeschlagen:" >&2
    tail -n 40 "$LOG_FILE" || true
    rm -f "$PID_FILE"
    exit 1
  fi
  if grep -q "Worker registriert:" "$LOG_FILE" 2>/dev/null; then
    echo "Worker läuft. PID: $pid"
    echo "Koordinator: ${BITTTS_COORDINATOR_URL:-?}"
    echo "Log: $LOG_FILE"
    exit 0
  fi
  sleep 1
done

echo "Worker läuft, Registrierung offen. Log: $LOG_FILE"
