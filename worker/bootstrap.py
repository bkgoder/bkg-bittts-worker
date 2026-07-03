from __future__ import annotations

import hashlib
import io
import json
import os
import stat
import subprocess
import sys
import zipfile
from pathlib import Path
from urllib.request import Request, urlopen

from worker.paths import RUNTIME_DIR

BUNDLE_DIR = Path(os.environ.get("BITTTS_BUNDLE_DIR", RUNTIME_DIR / "bundle")).resolve()
DIGEST_FILE = BUNDLE_DIR / ".bundle-sha256"
MANIFEST_FILE = BUNDLE_DIR / "worker-bundle.json"
TRAINING_BUNDLE_ENDPOINT = "/api/worker/training-bundle"


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


def _ensure_monotonic_align(upstream: Path) -> None:
    package = upstream / "monotonic_align"
    init_file = package / "__init__.py"
    setup_file = package / "setup.py"
    if not init_file.is_file() or not setup_file.is_file():
        return

    source = init_file.read_text(encoding="utf-8")
    lines = source.splitlines()
    normalized: list[str] = []
    replaced = False
    for line in lines:
        if "maximum_path_c" in line and line.lstrip().startswith("from "):
            if not replaced:
                normalized.append("from .core import maximum_path_c")
                replaced = True
            continue
        normalized.append(line)
    if not replaced:
        normalized.insert(2, "from .core import maximum_path_c")
    updated = "\n".join(normalized) + "\n"
    if updated != source:
        init_file.write_text(updated, encoding="utf-8")
        print("monotonic_align-Import repariert: from .core import maximum_path_c", flush=True)
    compile(updated, str(init_file), "exec")

    probe = subprocess.run(
        [sys.executable, "-c", "import monotonic_align"],
        cwd=upstream,
        text=True,
        capture_output=True,
        check=False,
    )
    if probe.returncode == 0:
        return

    print("Baue monotonic_align Cython-Erweiterung …", flush=True)
    subprocess.run(
        [
            sys.executable,
            "setup.py",
            "build_ext",
            "--build-lib",
            str(upstream),
        ],
        cwd=package,
        check=True,
    )
    probe = subprocess.run(
        [sys.executable, "-c", "import monotonic_align"],
        cwd=upstream,
        text=True,
        capture_output=True,
        check=False,
    )
    if probe.returncode != 0:
        detail = (probe.stderr or probe.stdout).strip()
        raise RuntimeError(f"monotonic_align konnte nicht geladen werden: {detail}")
    print("monotonic_align ist gebaut und importierbar.", flush=True)


def _patch_upstream_compat(root: Path) -> None:
    upstream = root / "vendor" / "MB-iSTFT-VITS"
    if not upstream.is_dir():
        return

    pqmf = upstream / "pqmf.py"
    if pqmf.is_file():
        source = pqmf.read_text(encoding="utf-8")
        lines = source.splitlines()
        anchor = next(
            (index for index, line in enumerate(lines) if line.strip() == "import torch.nn.functional as F"),
            None,
        )
        function = next(
            (index for index, line in enumerate(lines) if line.startswith("def design_prototype_filter")),
            None,
        )
        if anchor is None or function is None or function <= anchor:
            raise RuntimeError(f"Unbekanntes pqmf.py-Layout: {pqmf}")
        normalized = [
            *lines[: anchor + 1],
            "",
            "from scipy.signal.windows import kaiser",
            "",
            "",
            *lines[function:],
        ]
        updated = "\n".join(normalized) + "\n"
        if updated != source:
            pqmf.write_text(updated, encoding="utf-8")
            print("PQMF-Importblock repariert: scipy.signal.windows.kaiser", flush=True)
        compile(updated, str(pqmf), "exec")

    _ensure_monotonic_align(upstream)


def _bundle_ready(root: Path) -> bool:
    required = root / "scripts" / "mls-voice-trainer.sh"
    return required.is_file()


def ensure_training_bundle(coordinator_url: str, token: str, force: bool = False) -> Path:
    override = os.environ.get("BITTTS_SHUTUP_ROOT", "").strip()
    if override:
        root = Path(override).expanduser().resolve()
        if not _bundle_ready(root):
            raise RuntimeError(
                f"BITTTS_SHUTUP_ROOT ist gesetzt, aber unvollständig: {root}"
            )
        _patch_upstream_compat(root)
        print(f"Lokale Trainings-Engine: {root}", flush=True)
        return root

    base = coordinator_url.rstrip("/")
    BUNDLE_DIR.mkdir(parents=True, exist_ok=True)

    if not force:
        env_force = os.environ.get("BITTTS_BUNDLE_FORCE", "").strip().lower()
        force = env_force in {"1", "true", "yes", "on"}

    if not force and DIGEST_FILE.exists() and _bundle_ready(BUNDLE_DIR):
        _patch_upstream_compat(BUNDLE_DIR)
        print(
            "Lokales Trainings-Bundle bleibt unverändert. "
            "Für ein bewusstes Update: BITTTS_BUNDLE_FORCE=1",
            flush=True,
        )
        return BUNDLE_DIR

    request = Request(
        f"{base}{TRAINING_BUNDLE_ENDPOINT}",
        headers={
            "Authorization": f"Bearer {token}",
            "User-Agent": "bkg-bittts-worker/0.6.3",
            "Accept": "application/zip",
        },
    )
    with urlopen(request, timeout=180) as response:
        payload = response.read()
        digest = response.headers.get("X-BitTTS-Bundle-SHA256", "").strip()
        if not digest:
            digest = hashlib.sha256(payload).hexdigest()

    temp_dir = BUNDLE_DIR.with_name(f"{BUNDLE_DIR.name}.tmp")
    if temp_dir.exists():
        import shutil

        shutil.rmtree(temp_dir, ignore_errors=True)
    temp_dir.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        destination = temp_dir.resolve()
        for member in archive.infolist():
            target = (destination / member.filename).resolve()
            if target != destination and destination not in target.parents:
                raise RuntimeError(f"Unsicherer ZIP-Pfad: {member.filename}")
        archive.extractall(temp_dir)

    _chmod_scripts(temp_dir)
    _patch_upstream_compat(temp_dir)

    if not _bundle_ready(temp_dir):
        raise RuntimeError(
            "Trainings-Bundle unvollständig nach Download "
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
                f"Trainings-Bundle bereit: {len(manifest.get('files', []))} Dateien, "
                f"SHA256 {digest[:12]}…",
                flush=True,
            )
        except json.JSONDecodeError:
            pass
    else:
        print(f"Trainings-Bundle bereit unter {BUNDLE_DIR}", flush=True)

    return BUNDLE_DIR
