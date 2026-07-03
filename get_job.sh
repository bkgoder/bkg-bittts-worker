#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$ROOT/.env"
VENV_DIR="$ROOT/.venv"
REQ_FILE="$ROOT/requirements-gpu.txt"
REQ_HASH_FILE="$VENV_DIR/.bittts-requirements.sha256"
CALLER_BITTTS_AUTO_PULL="${BITTTS_AUTO_PULL-}"
CALLER_BITTTS_BUNDLE_FORCE="${BITTTS_BUNDLE_FORCE-}"

[[ -f "$ENV_FILE" ]] || {
  echo "FEHLER: .env fehlt. Zuerst ./get_home.sh ausführen." >&2
  exit 1
}

load_worker_env() {
  set -a
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  set +a

  export BITTTS_WORKER_RUNTIME="${BITTTS_WORKER_RUNTIME:-$ROOT/runtime}"
  export BITTTS_WORKER_DATASET="${BITTTS_WORKER_DATASET:-$ROOT/data/mls-german}"
  if [[ -n "$CALLER_BITTTS_AUTO_PULL" ]]; then
    export BITTTS_AUTO_PULL="$CALLER_BITTTS_AUTO_PULL"
  fi
  if [[ -n "$CALLER_BITTTS_BUNDLE_FORCE" ]]; then
    export BITTTS_BUNDLE_FORCE="$CALLER_BITTTS_BUNDLE_FORCE"
  else
    export BITTTS_BUNDLE_FORCE="${BITTTS_BUNDLE_FORCE:-0}"
  fi
}

load_worker_env

if [[ "${BITTTS_GET_JOB_ENV_DRY_RUN:-0}" == "1" ]]; then
  printf 'BITTTS_BUNDLE_FORCE=%s\n' "$BITTTS_BUNDLE_FORCE"
  exit 0
fi

if [[ "${BITTTS_AUTO_PULL:-0}" == "1" ]] && git -C "$ROOT" diff --quiet && git -C "$ROOT" diff --cached --quiet; then
  git -C "$ROOT" pull --ff-only
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  python3 -m venv --system-site-packages "$VENV_DIR"
fi

# Paperspace läuft im Notebook-Container als root. Die Venv bleibt trotzdem lokal im Repo.
export PIP_ROOT_USER_ACTION=ignore

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
current_hash="$(sha256sum "$REQ_FILE" | awk '{print $1}')"
installed_hash="$(cat "$REQ_HASH_FILE" 2>/dev/null || true)"
if [[ "$current_hash" != "$installed_hash" ]]; then
  python -m pip install --upgrade pip
  python -m pip install --upgrade -r "$REQ_FILE"
  printf '%s\n' "$current_hash" > "$REQ_HASH_FILE"
fi
python -m pip install -e "$ROOT"

python - <<'PY'
from importlib.metadata import version

expected = {
    "datasets": "3.2.0",
    "huggingface_hub": "0.27.1",
    "fsspec": "2024.9.0",
    "numpy": "1.26.4",
    "scipy": "1.10.1",
    "pandas": "2.2.0",
}
errors = []
for package, wanted in expected.items():
    found = version(package)
    print(f"{package}: {found}")
    if found != wanted:
        errors.append(f"{package}={found}, erwartet {wanted}")
if errors:
    raise SystemExit("Worker-Abhängigkeiten stimmen nicht: " + "; ".join(errors))

import torch
if not torch.cuda.is_available():
    raise SystemExit(
        "Keine CUDA-GPU erkannt. Auf Paperspace zuerst eine GPU-Maschine starten."
    )
print("GPU:", torch.cuda.get_device_name(0))
PY

mkdir -p "$BITTTS_WORKER_RUNTIME" "$BITTTS_WORKER_DATASET"

echo "Worker startet im Vordergrund."
echo "Name:        ${BITTTS_WORKER_NAME:-$(hostname)}"
echo "Coordinator: ${BITTTS_COORDINATOR_URL:-?}"
echo "Cache:       $BITTTS_WORKER_DATASET"

exec "$VENV_DIR/bin/bkg-bittts-worker" "$@"
