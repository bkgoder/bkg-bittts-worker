#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT="$(dirname "$ROOT")"
TARGET="$PARENT/bkg-bittts-worker-clean-$(date +%Y%m%d-%H%M%S)"

REPO_URL="$(git -C "$ROOT" remote get-url origin 2>/dev/null || printf '%s' 'https://github.com/bkgoder/bkg-bittts-worker.git')"

git clone "$REPO_URL" "$TARGET"

if [[ -f "$ROOT/.env" ]]; then
  cp "$ROOT/.env" "$TARGET/.env"
  chmod 600 "$TARGET/.env"
fi

echo "Saubere Worker-Kopie erstellt:"
echo "  $TARGET"
echo
echo "Weiter mit:"
echo "  cd '$TARGET'"
echo "  bash get_job.sh"
