#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"

usage() {
  cat <<'USAGE'
Nutzung:
  ./get_home.sh [TOKEN] [WORKER_NAME] [COORDINATOR]
  ./get_home.sh --count 3 [WORKER_NAME] [COORDINATOR]
  ./get_home.sh 3 [WORKER_NAME] [COORDINATOR]

Standard ohne TOKEN:
  Worker erstellt Join Requests beim Koordinator und wartet auf UI-Approve.

Expliziter Legacy/Managed-Token:
  ./get_home.sh bttw_xxx paperspace-gpu-01 https://train.eysho.info

Mehrere Worker:
  ./get_home.sh --count 3 paperspace-gpu-01 https://train.eysho.info

Dabei entstehen nach UI-Approve:
  BITTTS_WORKER_TOKEN_1=...
  BITTTS_WORKER_TOKEN_2=...
  BITTTS_WORKER_TOKEN_3=...
USAGE
}

COUNT=1
TOKEN=""
WORKER_NAME="${BITTTS_WORKER_NAME:-paperspace-gpu-01}"
COORDINATOR="${BITTTS_COORDINATOR_URL:-https://train.eysho.info}"
POLL_SECONDS="${BITTTS_JOIN_POLL_SECONDS:-10}"
JOIN_TIMEOUT_SECONDS="${BITTTS_JOIN_TIMEOUT_SECONDS:-1800}"
JOIN_USER_AGENT="${BITTTS_JOIN_USER_AGENT:-curl/8.5.0}"
EDGE_RETRY_SECONDS="${BITTTS_JOIN_EDGE_RETRY_SECONDS:-15}"
EDGE_RETRY_LIMIT="${BITTTS_JOIN_EDGE_RETRY_LIMIT:-40}"

if [[ $# -gt 0 ]]; then
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --count)
      COUNT="${2:?--count braucht eine Zahl}"
      shift 2
      ;;
    [0-9]*)
      COUNT="$1"
      shift
      ;;
  esac
fi

if (( COUNT == 1 )) && [[ $# -gt 0 && "${1:-}" == bttw_* ]]; then
  TOKEN="$1"
  shift
fi
if [[ $# -gt 0 ]]; then
  WORKER_NAME="$1"
  shift
fi
if [[ $# -gt 0 ]]; then
  COORDINATOR="$1"
  shift
fi
if [[ $# -gt 0 ]]; then
  echo "FEHLER: Zu viele Argumente." >&2
  usage >&2
  exit 2
fi

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || (( COUNT < 1 || COUNT > 64 )); then
  echo "FEHLER: Worker-Anzahl muss zwischen 1 und 64 liegen." >&2
  exit 2
fi

COORDINATOR="${COORDINATOR%/}"

write_env() {
  python3 - "$ENV_FILE" <<'PY'
from pathlib import Path
import os
import sys

path = Path(sys.argv[1])
values = {
    key: value
    for key, value in os.environ.items()
    if key.startswith('BITTTS_ENV_WRITE_')
}
normalized = {key.removeprefix('BITTTS_ENV_WRITE_'): value for key, value in values.items()}
existing = path.read_text(encoding='utf-8').splitlines() if path.exists() else []
out = []
seen = set()
for line in existing:
    key = line.split('=', 1)[0].strip() if '=' in line and not line.lstrip().startswith('#') else ''
    if key in normalized:
        out.append(f'{key}={normalized[key]}')
        seen.add(key)
    else:
        out.append(line)
for key, value in normalized.items():
    if key not in seen:
        out.append(f'{key}={value}')
path.write_text('\n'.join(out).rstrip() + '\n', encoding='utf-8')
path.chmod(0o600)
PY
}

join_and_wait_for_token() {
  local name="$1"
  python3 - "$COORDINATOR" "$name" "$POLL_SECONDS" "$JOIN_TIMEOUT_SECONDS" "$JOIN_USER_AGENT" "$EDGE_RETRY_SECONDS" "$EDGE_RETRY_LIMIT" <<'PY'
from __future__ import annotations

import json
import sys
import time
import urllib.error
import urllib.request

coordinator = sys.argv[1].rstrip('/')
name = sys.argv[2]
poll_seconds = max(1, int(sys.argv[3]))
timeout_seconds = max(30, int(sys.argv[4]))
user_agent = sys.argv[5]
edge_retry_seconds = max(1, int(sys.argv[6]))
edge_retry_limit = max(1, int(sys.argv[7]))

def request_json(method: str, path: str, payload: dict | None = None) -> dict:
    data = None if payload is None else json.dumps(payload).encode('utf-8')
    request = urllib.request.Request(
        f'{coordinator}{path}',
        data=data,
        headers={
            'Accept': 'application/json',
            'Cache-Control': 'no-cache',
            'Content-Type': 'application/json',
            'Pragma': 'no-cache',
            'User-Agent': user_agent,
        },
        method=method,
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            raw = response.read().decode('utf-8')
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as error:
        detail = error.read().decode('utf-8', errors='replace')
        if error.code == 403 and 'error code: 1010' in detail.lower():
            return {'_edge_blocked': True, '_method': method, '_path': path, '_detail': detail}
        if error.code in {403, 404, 405}:
            raise SystemExit(
                'JOIN_ENDPOINT_FAILED\n'
                f'{method} {path}\n'
                f'HTTP {error.code}: {detail}\n'
                'POST kann bereits funktionieren, aber GET-Poll/Approve kann noch fehlen oder blockiert sein.'
            )
        raise SystemExit(f'Join-Anfrage abgelehnt bei {method} {path}: HTTP {error.code}: {detail}')
    except Exception as error:
        raise SystemExit(f'Join-Anfrage fehlgeschlagen bei {method} {path}: {error}')

created = request_json('POST', '/api/worker/join-requests', {'name': name})
if created.get('_edge_blocked'):
    raise SystemExit(
        'JOIN_BLOCKED_BY_EDGE\n'
        'POST /api/worker/join-requests\n'
        f"{created.get('_detail')}\n"
        'Cloudflare/Edge blockt schon die Request-Erstellung. Proxy/WAF-Regel für /api/worker/join-requests prüfen.'
    )
request_id = str(created.get('id') or '').strip()
if not request_id:
    raise SystemExit('Koordinator hat keine Join-Request-ID zurückgegeben.')

print(f'Join Request erstellt: {name} ({request_id})', file=sys.stderr, flush=True)
print('Im Trainer-UI jetzt Approve klicken. Ja, ein Button, endlich Zivilisation.', file=sys.stderr, flush=True)

edge_blocks = 0
deadline = time.monotonic() + timeout_seconds
while time.monotonic() < deadline:
    current = request_json('GET', f'/api/worker/join-requests/{request_id}')
    if current.get('_edge_blocked'):
        edge_blocks += 1
        if edge_blocks > edge_retry_limit:
            raise SystemExit(
                'JOIN_BLOCKED_BY_EDGE\n'
                f"GET /api/worker/join-requests/{request_id}\n"
                f"{current.get('_detail')}\n"
                f'Edge blockt Polling dauerhaft nach {edge_blocks} Versuchen.'
            )
        print(
            f'Edge blockt Polling kurz ({edge_blocks}/{edge_retry_limit}); warte {edge_retry_seconds}s und versuche weiter.',
            file=sys.stderr,
            flush=True,
        )
        time.sleep(edge_retry_seconds)
        continue
    edge_blocks = 0
    status = str(current.get('status') or '').strip()
    token = str(current.get('token') or '').strip()
    if token:
        print(token)
        raise SystemExit(0)
    if status == 'denied':
        raise SystemExit(f'Worker-Freigabe wurde abgelehnt: {name}')
    if status in {'pending', 'approved', ''}:
        print(f'Warte auf Approve/Token fuer {name}: status={status or "unknown"}', file=sys.stderr, flush=True)
        time.sleep(poll_seconds)
        continue
    if status == 'claimed':
        raise SystemExit('Request ist bereits claimed, aber Token wurde nicht mehr geliefert. Erzeuge einen neuen Join Request.')
    raise SystemExit(f'Unerwarteter Join-Status fuer {name}: {status}')

raise SystemExit(f'Timeout: Keine Worker-Freigabe nach {timeout_seconds}s fuer {name}.')
PY
}

if [[ -z "$TOKEN" && "$COUNT" == "1" && -n "${BITTTS_WORKER_TOKEN:-}" ]]; then
  TOKEN="$BITTTS_WORKER_TOKEN"
fi

if (( COUNT == 1 )); then
  if [[ -z "$TOKEN" ]]; then
    echo "Kein Worker-Token angegeben. Erstelle Join Request für: $WORKER_NAME"
    TOKEN="$(join_and_wait_for_token "$WORKER_NAME")"
  fi
  if [[ ${#TOKEN} -lt 24 ]]; then
    echo "FEHLER: Worker-Token fehlt oder ist zu kurz." >&2
    exit 1
  fi
  export BITTTS_ENV_WRITE_BITTTS_WORKER_TOKEN="$TOKEN"
else
  echo "Erstelle $COUNT Worker Join Requests beim Koordinator. UI-Approve, dann ist Ruhe im Karton."
  for slot in $(seq 1 "$COUNT"); do
    token_var="BITTTS_WORKER_TOKEN_${slot}"
    existing_token="${!token_var:-}"
    if [[ -z "$existing_token" ]]; then
      existing_token="$(join_and_wait_for_token "${WORKER_NAME}-${slot}")"
    fi
    if [[ ${#existing_token} -lt 24 ]]; then
      echo "FEHLER: Token für Worker $slot fehlt oder ist zu kurz." >&2
      exit 1
    fi
    export "BITTTS_ENV_WRITE_BITTTS_WORKER_TOKEN_${slot}=$existing_token"
  done
fi

export BITTTS_ENV_WRITE_BITTTS_COORDINATOR_URL="$COORDINATOR"
export BITTTS_ENV_WRITE_BITTTS_WORKER_NAME="$WORKER_NAME"
export BITTTS_ENV_WRITE_BITTTS_WORKER_DATASET="data/mls-german"
export BITTTS_ENV_WRITE_BITTTS_DATASET_PROFILE="mls-german"
export BITTTS_ENV_WRITE_BITTTS_DATASET_SPLIT="9_hours"
export BITTTS_ENV_WRITE_BITTTS_MAX_HOURS="9.0"
export BITTTS_ENV_WRITE_BITTTS_WORKER_POLL_SECONDS="5"
export BITTTS_ENV_WRITE_BITTTS_BUNDLE_FORCE="0"

write_env

if command -v curl >/dev/null 2>&1; then
  curl -fsS "$COORDINATOR/api/health" >/dev/null || true
fi

echo "Worker verbunden."
echo "Name:        $WORKER_NAME"
echo "Coordinator: $COORDINATOR"
if (( COUNT == 1 )); then
  echo "Start:       ./get_job.sh"
else
  echo "Tokens:      BITTTS_WORKER_TOKEN_1..$COUNT in .env"
  echo "Start:       ./get_job.sh $COUNT"
  echo "Alias:       ./get_on.sh $COUNT"
fi
