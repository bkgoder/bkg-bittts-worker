#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

python3 -m py_compile worker/bootstrap.py worker/main.py
python3 -m unittest tests.test_bundle_force
