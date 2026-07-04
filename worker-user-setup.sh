#!/usr/bin/env bash
set -Eeuo pipefail

REPO_URL="${BITTTS_WORKER_REPO_URL:-https://github.com/bkgoder/bkg-bittts-worker.git}"
TARGET_DIR="${1:-${BITTTS_WORKER_DIR:-$PWD/bkg-bittts-worker}}"
COORDINATOR="${2:-${BITTTS_COORDINATOR_URL:-https://train.eysho.info}}"
WORKER_NAME="${3:-${BITTTS_WORKER_NAME:-$(hostname)}}"
COUNT="${4:-${BITTTS_WORKER_COUNT:-1}}"

usage() {
  cat <<'USAGE'
Nutzung:
  bash worker-user-setup.sh [TARGET_DIR] [COORDINATOR_URL] [WORKER_NAME] [COUNT]

Beispiele:
  bash worker-user-setup.sh
  bash worker-user-setup.sh /notebooks/bkg-bittts-worker https://train.eysho.info paperspace-gpu-01 3

Macht:
  - Repo klonen oder aktualisieren
  - Python venv anlegen
  - requirements-gpu.txt installieren/reparieren
  - Worker lokal editable installieren
  - get_home.sh Join/Token-Flow ausführen
  - danach Startbefehl anzeigen
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || (( COUNT < 1 || COUNT > 64 )); then
  echo "FEHLER: COUNT muss zwischen 1 und 64 liegen." >&2
  exit 2
fi

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "FEHLER: '$1' fehlt. Installier das erst, sonst wird das hier wieder moderne Höhlenmalerei." >&2
    exit 1
  }
}

need_cmd git
need_cmd python3

if [[ -d "$TARGET_DIR/.git" ]]; then
  echo "Repo aktualisieren: $TARGET_DIR"
  git -C "$TARGET_DIR" pull --ff-only
else
  echo "Repo klonen: $REPO_URL -> $TARGET_DIR"
  mkdir -p "$(dirname "$TARGET_DIR")"
  git clone "$REPO_URL" "$TARGET_DIR"
fi

cd "$TARGET_DIR"
chmod +x get_home.sh get_job.sh get_on.sh 2>/dev/null || true

VENV_DIR="$TARGET_DIR/.venv"
REQ_FILE="$TARGET_DIR/requirements-gpu.txt"
REQ_HASH_FILE="$VENV_DIR/.bittts-requirements.sha256"

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "Venv anlegen: $VENV_DIR"
  python3 -m venv --system-site-packages "$VENV_DIR"
fi

# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
export PIP_ROOT_USER_ACTION=ignore

install_requirements() {
  local mode="${1:-normal}"
  python -m pip install --upgrade pip
  if [[ "$mode" == "repair" ]]; then
    python -m pip install --upgrade --force-reinstall --no-cache-dir -r "$REQ_FILE"
  else
    python -m pip install --upgrade -r "$REQ_FILE"
  fi
}

check_requirements() {
  python - <<'PY'
from importlib.metadata import PackageNotFoundError, version
expected = {
    "datasets": "3.2.0",
    "huggingface_hub": "0.27.1",
    "fsspec": "2024.9.0",
    "numpy": "1.26.4",
    "scipy": "1.13.1",
    "pandas": "2.2.0",
}
errors = []
for package, wanted in expected.items():
    try:
        found = version(package)
    except PackageNotFoundError:
        found = "nicht installiert"
    print(f"{package}: {found}")
    if found != wanted:
        errors.append(f"{package}={found}, erwartet {wanted}")
if errors:
    raise SystemExit("Worker-Abhängigkeiten stimmen nicht: " + "; ".join(errors))
PY
}

current_hash="$(sha256sum "$REQ_FILE" | awk '{print $1}')"
installed_hash="$(cat "$REQ_HASH_FILE" 2>/dev/null || true)"
if [[ "$current_hash" != "$installed_hash" ]]; then
  echo "Requirements installieren. Python macht Python-Dinge, wir leiden kurz professionell."
  install_requirements normal
  printf '%s\n' "$current_hash" > "$REQ_HASH_FILE"
fi

if ! check_requirements; then
  echo "Requirements reparieren. Weil Versionen offenbar Gefühle haben."
  rm -f "$REQ_HASH_FILE"
  install_requirements repair
  check_requirements
  printf '%s\n' "$current_hash" > "$REQ_HASH_FILE"
fi

python -m pip install -e "$TARGET_DIR"

if python - <<'PY'
import torch
raise SystemExit(0 if torch.cuda.is_available() else 1)
PY
then
  python - <<'PY'
import torch
print("GPU:", torch.cuda.get_device_name(0))
PY
else
  echo "WARNUNG: Keine CUDA-GPU erkannt. Setup ist fertig, Training aber nicht sinnvoll ohne GPU." >&2
fi

if (( COUNT == 1 )); then
  ./get_home.sh "" "$WORKER_NAME" "$COORDINATOR"
else
  ./get_home.sh --count "$COUNT" "$WORKER_NAME" "$COORDINATOR"
fi

cat <<EOF

Fertig.

Repo:
  cd $TARGET_DIR

Start:
  ./get_job.sh $([[ "$COUNT" == "1" ]] || printf '%s' "$COUNT")

Alias:
  ./get_on.sh $([[ "$COUNT" == "1" ]] || printf '%s' "$COUNT")

Logs bei mehreren Workern:
  tail -f runtime/multi-worker/worker-*.log
EOF
