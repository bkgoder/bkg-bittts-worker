#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"
COORDINATOR="${3:-${BITTTS_COORDINATOR_URL:-https://train.eysho.info}}"
WORKER_NAME="${2:-${BITTTS_WORKER_NAME:-paperspace-gpu-01}}"
TOKEN="${1:-${BITTTS_WORKER_TOKEN:-}}"

if [[ -z "$TOKEN" && -t 0 ]]; then
  read -rsp "Worker-Token: " TOKEN
  echo
fi

if [[ ${#TOKEN} -lt 24 ]]; then
  echo "FEHLER: Worker-Token fehlt oder ist zu kurz." >&2
  echo "Token im Trainer unter https://train.eysho.info/ui/ erzeugen." >&2
  exit 1
fi

python3 - "$ENV_FILE" "$COORDINATOR" "$TOKEN" "$WORKER_NAME" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
values = {
    "BITTTS_COORDINATOR_URL": sys.argv[2].rstrip("/"),
    "BITTTS_WORKER_TOKEN": sys.argv[3],
    "BITTTS_WORKER_NAME": sys.argv[4],
    "BITTTS_WORKER_DATASET": "data/mls-german",
    "BITTTS_DATASET_PROFILE": "mls-german",
    "BITTTS_DATASET_SPLIT": "9_hours",
    "BITTTS_MAX_HOURS": "9.0",
    "BITTTS_WORKER_POLL_SECONDS": "5",
    "BITTTS_BUNDLE_FORCE": "0",
}

existing = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
out = []
seen = set()
for line in existing:
    key = line.split("=", 1)[0].strip() if "=" in line and not line.lstrip().startswith("#") else ""
    if key in values:
        out.append(f"{key}={values[key]}")
        seen.add(key)
    else:
        out.append(line)
for key, value in values.items():
    if key not in seen:
        out.append(f"{key}={value}")
path.write_text("\n".join(out).rstrip() + "\n", encoding="utf-8")
path.chmod(0o600)
PY

if command -v curl >/dev/null 2>&1; then
  curl -fsS "$COORDINATOR/api/health" >/dev/null
fi

echo "Worker verbunden."
echo "Name:        $WORKER_NAME"
echo "Coordinator: $COORDINATOR"
echo "Start:       ./get_job.sh"
