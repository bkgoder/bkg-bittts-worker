from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
RUNTIME_DIR = Path(os.environ.get("BITTTS_WORKER_RUNTIME", REPO_ROOT / "runtime")).resolve()
ENV_FILE = Path(os.environ.get("BITTTS_ENV_FILE", REPO_ROOT / ".env")).resolve()
