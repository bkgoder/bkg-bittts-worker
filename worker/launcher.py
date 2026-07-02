from __future__ import annotations

import hashlib
import os

from worker.main import main as worker_main


def main() -> None:
    token = os.environ.get("BITTTS_WORKER_TOKEN", "").strip()
    configured = os.environ.get("BITTTS_WORKER_ID", "").strip()
    if not configured and token.startswith("bttw_"):
        identity = hashlib.sha256(token.encode("utf-8")).hexdigest()[:24]
        os.environ["BITTTS_WORKER_ID"] = f"managed-{identity}"
    worker_main()


if __name__ == "__main__":
    main()
