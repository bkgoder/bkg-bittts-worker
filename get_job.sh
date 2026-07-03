#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"
VENV_DIR="$ROOT/.venv"

[[ -f "$ENV_FILE" ]] || {
  echo "FEHLER: .env fehlt. Zuerst ./get_home.sh ausführen." >&2
  exit 1
}

if [[ "${BITTTS_AUTO_PULL:-0}" == "1" ]] && git -C "$ROOT" diff --quiet && git -C "$ROOT" diff --cached --quiet; then
  git -C "$ROOT" pull --ff-only
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  python3 -m venv --system-site-packages "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip wheel setuptools
python -m pip install --upgrade --force-reinstall -r "$ROOT/requirements-gpu.txt"
python -m pip install -e "$ROOT"

python - <<'PY'
import torch
if not torch.cuda.is_available():
    raise SystemExit(
        "Keine CUDA-GPU erkannt. Auf Paperspace zuerst eine GPU-Maschine starten."
    )
print("GPU:", torch.cuda.get_device_name(0))
PY

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

export BITTTS_WORKER_RUNTIME="${BITTTS_WORKER_RUNTIME:-$ROOT/runtime}"
export BITTTS_WORKER_DATASET="${BITTTS_WORKER_DATASET:-$ROOT/data/mls-german}"
export BITTTS_BUNDLE_FORCE="${BITTTS_BUNDLE_FORCE:-0}"
mkdir -p "$BITTTS_WORKER_RUNTIME" "$BITTTS_WORKER_DATASET"

echo "Worker startet im Vordergrund."
echo "Name:        ${BITTTS_WORKER_NAME:-$(hostname)}"
echo "Coordinator: ${BITTTS_COORDINATOR_URL:-?}"
echo "Cache:       $BITTTS_WORKER_DATASET"

exec "$VENV_DIR/bin/bkg-bittts-worker" "$@"
