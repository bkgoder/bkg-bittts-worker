#!/usr/bin/env bash
set -Eeuo pipefail

mkdir -p /runtime /data /runtime/bundle "${BITTTS_WORKER_DATASET:-/data/mls-german}"

if [[ -n "${BITTTS_SHUTUP_ROOT:-}" && -d "${BITTTS_SHUTUP_ROOT}/scripts/mls-voice-trainer.sh" ]]; then
  echo "[worker-docker] BITTTS_SHUTUP_ROOT=${BITTTS_SHUTUP_ROOT}"
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi -L || true
else
  echo "[worker-docker] Warnung: nvidia-smi nicht verfügbar — GPU evtl. nicht durchgereicht." >&2
fi

exec bkg-bittts-worker "$@"
