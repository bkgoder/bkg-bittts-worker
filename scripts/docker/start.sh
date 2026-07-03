#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail() { echo "[BitTTS Worker Docker] FEHLER: $*" >&2; exit 1; }

command -v docker >/dev/null || fail "docker fehlt"
docker compose version >/dev/null 2>&1 || fail "docker compose (v2) fehlt"

if ! docker info 2>/dev/null | grep -qi 'nvidia'; then
  if ! docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi >/dev/null 2>&1; then
    echo "[BitTTS Worker Docker] Warnung: GPU-Test fehlgeschlagen." >&2
    echo "  NVIDIA Container Toolkit installieren: https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/install-guide.html" >&2
  fi
fi

[[ -f .env ]] || {
  cp .env.example .env
  echo "[BitTTS Worker Docker] .env erstellt — BITTTS_WORKER_TOKEN eintragen."
  fail "BITTTS_WORKER_TOKEN in .env setzen, dann erneut starten."
}

set -a
# shellcheck disable=SC1091
source .env
set +a
[[ -n "${BITTTS_WORKER_TOKEN:-}" ]] || fail "BITTTS_WORKER_TOKEN fehlt in .env"

docker compose build
docker compose up -d

echo ""
echo "Worker-Container läuft (GPU)."
echo "  Logs:   bash scripts/docker/logs.sh"
echo "  Status: bash scripts/docker/status.sh"
echo "  Stop:   bash scripts/docker/stop.sh"
