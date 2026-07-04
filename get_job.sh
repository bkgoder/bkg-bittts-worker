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

usage() {
  cat <<'USAGE'
Nutzung:
  ./get_job.sh                         # einen Worker im Vordergrund starten
  ./get_job.sh 3                       # drei Worker im Hintergrund starten
  ./get_job.sh --count 3               # dasselbe, nur weniger kryptisch
  ./get_job.sh 3 --foreground          # drei Worker starten und Logs live anzeigen
  ./get_job.sh 3 --follow              # Alias für --foreground
  ./get_job.sh 3 -- --once             # drei Worker starten, je nur einen Job

Mehrere Worker:
  - Jeder Worker bekommt automatisch einen eindeutigen Namen und eine stabile Worker-ID.
  - Die stabile Default-ID basiert auf BITTTS_WORKER_NAME, nicht auf dem Container-Hostname.
  - Jeder Worker bekommt einen eigenen MASTER_PORT und BITTTS_MASTER_PORT.
  - Logs landen unter runtime/multi-worker/worker-N.log.
  - PIDs landen unter runtime/multi-worker/worker-N.pid.
  - Bei Managed Worker Tokens braucht jeder Slot einen eigenen Token:
      BITTTS_WORKER_TOKEN_1=...
      BITTTS_WORKER_TOKEN_2=...
      BITTTS_WORKER_TOKEN_3=...

Achtung:
  Mehrere Trainingsjobs auf einer einzelnen GPU können CUDA-OOM auslösen.
USAGE
}

WORKER_COUNT=1
WORKER_ARGS=()
FOLLOW_LOGS=0
if [[ $# -gt 0 ]]; then
  case "${1:-}" in
    -h|--help)
      usage
      exit 0
      ;;
    --count)
      WORKER_COUNT="${2:?--count braucht eine Zahl}"
      shift 2
      ;;
    --foreground|--follow)
      FOLLOW_LOGS=1
      shift
      ;;
    --)
      shift
      ;;
    '' )
      ;;
    * )
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        WORKER_COUNT="$1"
        shift
      fi
      ;;
  esac
fi
while [[ $# -gt 0 ]]; do
  case "${1:-}" in
    --foreground|--follow)
      FOLLOW_LOGS=1
      shift
      ;;
    --)
      shift
      WORKER_ARGS=("$@")
      break
      ;;
    *)
      WORKER_ARGS+=("$1")
      shift
      ;;
  esac
done

if ! [[ "$WORKER_COUNT" =~ ^[0-9]+$ ]] || (( WORKER_COUNT < 1 || WORKER_COUNT > 64 )); then
  echo "FEHLER: Worker-Anzahl muss zwischen 1 und 64 liegen." >&2
  exit 2
fi

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

export PIP_ROOT_USER_ACTION=ignore
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"

install_requirements() {
  local mode="${1:-normal}"
  python -m pip install --upgrade pip
  if [[ "$mode" == "repair" ]]; then
    echo "Worker-Abhängigkeiten werden repariert. Python-Pakete, das ewige Steckdosenziehen im Maschinenraum."
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
  install_requirements normal
  printf '%s\n' "$current_hash" > "$REQ_HASH_FILE"
fi

if ! check_requirements; then
  rm -f "$REQ_HASH_FILE"
  install_requirements repair
  check_requirements
  printf '%s\n' "$current_hash" > "$REQ_HASH_FILE"
fi

python -m pip install -e "$ROOT"

python - <<'PY'
import torch
if not torch.cuda.is_available():
    raise SystemExit(
        "Keine CUDA-GPU erkannt. Auf Paperspace zuerst eine GPU-Maschine starten."
    )
print("GPU:", torch.cuda.get_device_name(0))
PY

mkdir -p "$BITTTS_WORKER_RUNTIME" "$BITTTS_WORKER_DATASET"

base_worker_name="${BITTTS_WORKER_NAME:-$(hostname)}"
base_worker_id="${BITTTS_WORKER_ID:-$base_worker_name}"
base_master_port="${MASTER_PORT:-65520}"
if ! [[ "$base_master_port" =~ ^[0-9]+$ ]]; then
  echo "FEHLER: MASTER_PORT muss eine Zahl sein." >&2
  exit 2
fi

if (( WORKER_COUNT == 1 )); then
  export BITTTS_WORKER_ID="$base_worker_id"
  export MASTER_ADDR="${MASTER_ADDR:-127.0.0.1}"
  export MASTER_PORT="$base_master_port"
  export BITTTS_MASTER_PORT="$MASTER_PORT"
  echo "Worker startet im Vordergrund."
  echo "Name:        $base_worker_name"
  echo "ID:          $BITTTS_WORKER_ID"
  echo "Coordinator: ${BITTTS_COORDINATOR_URL:-?}"
  echo "Cache:       $BITTTS_WORKER_DATASET"
  echo "MASTER:      $MASTER_ADDR:$MASTER_PORT"
  exec "$VENV_DIR/bin/bkg-bittts-worker" "${WORKER_ARGS[@]}"
fi

multi_dir="$BITTTS_WORKER_RUNTIME/multi-worker"
mkdir -p "$multi_dir"

declare -A seen_tokens=()
for slot in $(seq 1 "$WORKER_COUNT"); do
  token_var="BITTTS_WORKER_TOKEN_${slot}"
  slot_token="${!token_var:-}"
  if [[ -z "$slot_token" ]]; then
    echo "FEHLER: $token_var fehlt." >&2
    echo "Multi-Worker mit Managed Tokens braucht pro Worker einen eigenen Token." >&2
    echo "Führe aus: ./get_home.sh --count $WORKER_COUNT $base_worker_name ${BITTTS_COORDINATOR_URL:-https://train.eysho.info}" >&2
    exit 1
  fi
  if [[ -n "${seen_tokens[$slot_token]:-}" ]]; then
    echo "FEHLER: $token_var ist identisch mit BITTTS_WORKER_TOKEN_${seen_tokens[$slot_token]}." >&2
    echo "Managed Tokens dürfen nicht mehrfach verwendet werden." >&2
    exit 1
  fi
  seen_tokens[$slot_token]="$slot"
done

printf 'Starte %s Worker. Mehrere Prozesse, weil ein einzelner offenbar zu zivilisiert war.\n' "$WORKER_COUNT"
echo "Name-Basis:   $base_worker_name"
echo "ID-Basis:     $base_worker_id"
echo "Coordinator: ${BITTTS_COORDINATOR_URL:-?}"
echo "Cache:       $BITTTS_WORKER_DATASET"
echo "Logs:        $multi_dir"
echo "Live-Logs:   $FOLLOW_LOGS"

pids=()
cleanup() {
  if (( ${#pids[@]} > 0 )); then
    echo
    echo "Stoppe Worker: ${pids[*]}"
    kill "${pids[@]}" 2>/dev/null || true
  fi
}
if (( FOLLOW_LOGS == 1 )); then
  trap cleanup INT TERM EXIT
fi

for slot in $(seq 1 "$WORKER_COUNT"); do
  token_var="BITTTS_WORKER_TOKEN_${slot}"
  slot_token="${!token_var}"
  slot_master_port=$((base_master_port + slot))

  log_file="$multi_dir/worker-${slot}.log"
  pid_file="$multi_dir/worker-${slot}.pid"

  (
    export BITTTS_WORKER_SLOT="$slot"
    export BITTTS_WORKER_TOKEN="$slot_token"
    export BITTTS_WORKER_NAME="${base_worker_name}-${slot}"
    export BITTTS_WORKER_ID="${base_worker_id}-${slot}"
    export MASTER_ADDR="${MASTER_ADDR:-127.0.0.1}"
    export MASTER_PORT="$slot_master_port"
    export BITTTS_MASTER_PORT="$slot_master_port"

    echo "[$(date -Is)] Starte Worker $slot"
    echo "Name:          $BITTTS_WORKER_NAME"
    echo "ID:            $BITTTS_WORKER_ID"
    echo "MASTER:        $MASTER_ADDR:$MASTER_PORT"
    echo "BITTTS_MASTER: $BITTTS_MASTER_PORT"
    exec "$VENV_DIR/bin/bkg-bittts-worker" "${WORKER_ARGS[@]}"
  ) >"$log_file" 2>&1 &
  pid="$!"
  pids+=("$pid")
  printf '%s\n' "$pid" > "$pid_file"
  echo "Worker $slot gestartet: pid=$pid master_port=$slot_master_port log=$log_file"
done

cat <<EOF

Status:
  ps -fp \$(cat $multi_dir/worker-*.pid)

Logs:
  tail -f $multi_dir/worker-1.log
  tail -f $multi_dir/worker-*.log

Stop:
  kill \$(cat $multi_dir/worker-*.pid)
EOF

if (( FOLLOW_LOGS == 1 )); then
  echo
  echo "Live-Modus aktiv. Strg+C stoppt alle gestarteten Worker. Mensch gegen Prozessbaum, Klassiker."
  tail -n +1 -f "$multi_dir"/worker-*.log &
  tail_pid="$!"
  while true; do
    alive=0
    for pid in "${pids[@]}"; do
      if kill -0 "$pid" 2>/dev/null; then
        alive=1
      fi
    done
    if (( alive == 0 )); then
      kill "$tail_pid" 2>/dev/null || true
      wait "$tail_pid" 2>/dev/null || true
      trap - INT TERM EXIT
      exit 0
    fi
    sleep 2
  done
fi
