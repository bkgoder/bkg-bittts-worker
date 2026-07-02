#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$ROOT/.env"
VENV_DIR="$ROOT/.venv"
RUNTIME_DIR="$ROOT/runtime"
PID_FILE="$RUNTIME_DIR/worker.pid"
LOG_FILE="$RUNTIME_DIR/worker.log"

fail() { echo "[BitTTS Worker] FEHLER: $*" >&2; exit 1; }

command -v python3 >/dev/null || fail "python3 fehlt"

if [[ ! -f "$ENV_FILE" ]]; then
  cp "$ROOT/.env.example" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  echo "[BitTTS Worker] .env erstellt — Token und BITTTS_SHUTUP_ROOT eintragen."
fi

mkdir -p "$RUNTIME_DIR"

if [[ ! -d "$VENV_DIR" ]]; then
  python3 -m venv "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
python -m pip install --upgrade pip wheel
python -m pip install -e "$ROOT"

set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

if [[ -z "${BITTTS_SHUTUP_ROOT:-}" || ! -d "$BITTTS_SHUTUP_ROOT" ]]; then
  echo "[BitTTS Worker] Warnung: BITTTS_SHUTUP_ROOT fehlt in .env"
fi

echo "[BitTTS Worker] Install fertig."
echo "  bash scripts/linux/start.sh"
