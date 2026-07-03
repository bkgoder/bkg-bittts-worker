#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

echo "=== BKG BitTTS Worker (Docker) ==="
docker compose ps

cid="$(docker compose ps -q worker 2>/dev/null || true)"
if [[ -n "$cid" ]]; then
  echo ""
  echo "GPU im Container:"
  docker exec "$cid" nvidia-smi -L 2>/dev/null || echo "  nvidia-smi nicht verfügbar"
  echo ""
  echo "Letzte Logzeilen:"
  docker compose logs --tail=15 worker
fi
