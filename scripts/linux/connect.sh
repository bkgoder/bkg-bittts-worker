#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOG_FILE="$ROOT/runtime/worker.log"
touch "$LOG_FILE"
exec tail -n 50 -f "$LOG_FILE"
