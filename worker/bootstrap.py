from __future__ import annotations

import hashlib
import io
import json
import os
import stat
import zipfile
from pathlib import Path
from urllib.request import Request, urlopen

from worker.paths import RUNTIME_DIR

BUNDLE_DIR = Path(os.environ.get("BITTTS_BUNDLE_DIR", RUNTIME_DIR / "bundle")).resolve()
DIGEST_FILE = BUNDLE_DIR / ".bundle-sha256"
MANIFEST_FILE = BUNDLE_DIR / "worker-bundle.json"


def training_root() -> Path:
    override = os.environ.get("BITTTS_SHUTUP_ROOT", "").strip()
    if override:
        return Path(override).expanduser().resolve()
    return BUNDLE_DIR


def _chmod_scripts(root: Path) -> None:
    scripts = root / "scripts"
    if not scripts.is_dir():
        return
    for path in scripts.glob("*.sh"):
        try:
            path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        except OSError:
            pass


def _bundle_ready(root: Path) -> bool:
    required = root / "scripts" / "mls-voice-trainer.sh"
    return required.is_file()


def ensure_training_bundle(coordinator_url: str, token: str, force: bool = False) -> Path:
    base = coordinator_url.rstrip("/")
    BUNDLE_DIR.mkdir(parents=True, exist_ok=True)

    if not force:
        env_force = os.environ.get("BITTTS_BUNDLE_FORCE", "").strip().lower()
        force = env_force in {"1", "true", "yes", "on"}

    if not force and DIGEST_FILE.exists() and _bundle_ready(BUNDLE_DIR):
        return BUNDLE_DIR

    request = Request(
        f"{base}/api/worker/bootstrap",
        headers={
            "Authorization": f"Bearer {token}",
            "User-Agent": "bkg-bittts-worker/0.5.1",
            "Accept": "application/zip",
        },
    )
    with urlopen(request, timeout=120) as response:
        payload = response.read()
        digest = response.headers.get("X-BitTTS-Bundle-SHA256", "").strip()
        if not digest:
            digest = hashlib.sha256(payload).hexdigest()

    if (
        not force
        and DIGEST_FILE.exists()
        and DIGEST_FILE.read_text(encoding="utf-8").strip() == digest
        and _bundle_ready(BUNDLE_DIR)
    ):
        return BUNDLE_DIR

    temp_dir = BUNDLE_DIR.with_name(f"{BUNDLE_DIR.name}.tmp")
    if temp_dir.exists():
        import shutil

        shutil.rmtree(temp_dir, ignore_errors=True)
    temp_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        archive.extractall(temp_dir)

    _chmod_scripts(temp_dir)

    if not _bundle_ready(temp_dir):
        raise RuntimeError(
            "Worker-Bundle unvollständig nach Download "
            f"(scripts/mls-voice-trainer.sh fehlt in {temp_dir})."
        )

    import shutil

    if BUNDLE_DIR.exists():
        shutil.rmtree(BUNDLE_DIR, ignore_errors=True)
    temp_dir.replace(BUNDLE_DIR)
    DIGEST_FILE.write_text(digest + "\n", encoding="utf-8")

    if MANIFEST_FILE.exists():
        try:
            manifest = json.loads(MANIFEST_FILE.read_text(encoding="utf-8"))
            print(
                f"Training-Bundle bereit: {len(manifest.get('files', []))} Dateien, SHA256 {digest[:12]}…",
                flush=True,
            )
        except json.JSONDecodeError:
            pass
    else:
        print(f"Training-Bundle bereit unter {BUNDLE_DIR}", flush=True)

    return BUNDLE_DIR
