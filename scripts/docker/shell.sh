#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
cid="$(docker compose ps -q worker)"
[[ -n "$cid" ]] || { echo "Worker-Container läuft nicht." >&2; exit 1; }
exec docker exec -it "$cid" bash
