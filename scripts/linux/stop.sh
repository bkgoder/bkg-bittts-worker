#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PID_FILE="$ROOT/runtime/worker.pid"
[[ -f "$PID_FILE" ]] || { echo "Kein Worker aktiv."; exit 0; }
pid="$(cat "$PID_FILE")"
kill "$pid" 2>/dev/null || true
rm -f "$PID_FILE"
echo "Worker gestoppt."
