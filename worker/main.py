from __future__ import annotations

import argparse
import os
import platform
import re
import shutil
import signal
import socket
import subprocess
import sys
import threading
import time
import uuid
from pathlib import Path
from typing import Any

from worker.bootstrap import ensure_training_bundle, training_root
from worker.client import CoordinatorClient
from worker.paths import REPO_ROOT, RUNTIME_DIR

ROOT = REPO_ROOT
RUNTIME = RUNTIME_DIR
RUNTIME.mkdir(parents=True, exist_ok=True)
WORKER_ID_FILE = RUNTIME / "worker-id"
WORKER_RUNTIME_VERSION = "2026-07-03-remote-bundle"
STOP_REQUESTED = threading.Event()
PROCESS_LOCK = threading.Lock()
CURRENT_PROCESS: subprocess.Popen[str] | None = None
IS_WINDOWS = sys.platform == "win32"


def terminate_process(process: subprocess.Popen[str], timeout: int = 20) -> None:
    if process.poll() is not None:
        return
    if IS_WINDOWS:
        process.terminate()
        try:
            process.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=10)
        return
    try:
        os.killpg(process.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        process.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.wait(timeout=10)


def handle_signal(signum: int, _frame: object) -> None:
    STOP_REQUESTED.set()
    with PROCESS_LOCK:
        process = CURRENT_PROCESS
    if process is not None:
        terminate_process(process)
    print(f"Worker beendet sich nach Signal {signum}.", flush=True)


def detect_gpu() -> tuple[bool, str]:
    try:
        result = subprocess.run(
            ["nvidia-smi", "--query-gpu=name,memory.total", "--format=csv,noheader"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=10,
            check=False,
        )
        value = result.stdout.strip()
        if result.returncode == 0 and value:
            return True, value
    except (FileNotFoundError, subprocess.TimeoutExpired):
        pass

    try:
        import torch

        if torch.cuda.is_available():
            name = torch.cuda.get_device_name(0)
            memory = torch.cuda.get_device_properties(0).total_memory // (1024 * 1024)
            return True, f"{name}, {memory} MiB"
    except Exception:
        pass
    return False, "keine CUDA-GPU erkannt"


def worker_id() -> str:
    configured = os.environ.get("BITTTS_WORKER_ID", "").strip()
    if configured:
        return configured
    if WORKER_ID_FILE.exists():
        existing = WORKER_ID_FILE.read_text(encoding="utf-8").strip()
        if existing:
            return existing
    generated = uuid.uuid4().hex
    WORKER_ID_FILE.write_text(generated, encoding="utf-8")
    return generated


def resolve_worker_dataset(configured: str = "", profile: str = "mls-german") -> str:
    configured = configured.strip()
    if not configured:
        return str(ROOT / "data" / profile)
    path = Path(configured)
    if path.is_absolute() or configured.startswith(("./", "../")):
        return str(path)
    if "/" in configured or (IS_WINDOWS and "\\" in configured):
        return str((ROOT / configured).resolve())
    return str(ROOT / "data" / configured)


def worker_metadata(gpu_name: str) -> dict[str, Any]:
    return {
        "hostname": socket.gethostname(),
        "platform": platform.platform(),
        "python": sys.executable,
        "gpu_name": gpu_name,
        "dataset": resolve_worker_dataset(
            os.environ.get("BITTTS_WORKER_DATASET", ""),
            os.environ.get("BITTTS_DATASET_PROFILE", "mls-german"),
        ),
        "profiles": ["mls-german", "thorsten-legacy"],
    }


def safe_name(value: str) -> str:
    normalized = re.sub(r"[^A-Za-z0-9._-]+", "-", value.strip())
    return normalized.strip("-.") or "auto"


def bash_runner() -> list[str]:
    if not IS_WINDOWS:
        return ["bash"]
    if shutil.which("bash"):
        return ["bash"]
    if shutil.which("wsl"):
        return ["wsl", "bash"]
    raise RuntimeError(
        "Unter Windows wird bash oder WSL benötigt (Git Bash / WSL). "
        "Trainingsskripte kommen per Remote-Bootstrap vom Koordinator."
    )


def shell_script_command(script: Path, *args: str) -> list[str]:
    if not script.is_file():
        raise FileNotFoundError(f"Skript fehlt: {script}")
    return [*bash_runner(), str(script), *args]


def job_command(job: dict[str, Any]) -> tuple[list[str], dict[str, str]]:
    action = str(job["action"])
    payload = job.get("payload") or {}
    profile = str(payload.get("dataset_profile") or "mls-german")
    bundle_root = training_root()
    if profile == "mls-german":
        script = bundle_root / "scripts" / "mls-voice-trainer.sh"
    elif profile == "thorsten-legacy":
        script = bundle_root / "scripts" / "translate-voice-trainer.sh"
    else:
        raise ValueError(f"Unbekanntes Dataset-Profil: {profile}")

    command_map = {
        "download": shell_script_command(script, "--download-only"),
        "prepare": shell_script_command(script, "--prepare-only"),
        "train": shell_script_command(script, "--train-only"),
        "full": shell_script_command(script),
    }
    if action not in command_map:
        raise ValueError(f"Unbekannte Job-Aktion: {action}")

    speaker_id = str(payload.get("speaker_id") or "").strip()
    default_voice = f"de-mls-{safe_name(speaker_id)}" if profile == "mls-german" else "de-default"
    env = os.environ.copy()
    env["BITTTS_PYTHON"] = sys.executable
    env["BITTTS_DATASET_PROFILE"] = profile
    env["BITTTS_WORKER_DATASET"] = resolve_worker_dataset(
        os.environ.get("BITTTS_WORKER_DATASET", ""),
        profile,
    )
    env["BITTTS_OUTPUT_VOICE"] = str(payload.get("output_voice") or default_voice)
    if payload.get("model_tag"):
        env["BITTTS_TRAIN_MODEL"] = str(payload["model_tag"])

    if profile == "mls-german":
        env["BITTTS_DATASET_ID"] = str(
            payload.get("dataset_id") or "facebook/multilingual_librispeech"
        )
        env["BITTTS_DATASET_CONFIG"] = str(payload.get("dataset_config") or "german")
        env["BITTTS_DATASET_SPLIT"] = str(
            payload.get("split")
            or os.environ.get("BITTTS_DATASET_SPLIT")
            or "9_hours"
        )
        env["BITTTS_SPEAKER_ID"] = speaker_id
        env["BITTTS_MAX_HOURS"] = str(
            payload.get("max_hours")
            or os.environ.get("BITTTS_MAX_HOURS")
            or 9.0
        )
        env["BITTTS_SCAN_ROWS"] = str(payload.get("scan_rows") or 5000)
    else:
        env["BITTTS_THORSTEN_DIR"] = env["BITTTS_WORKER_DATASET"]

    return command_map[action], env


def heartbeat_loop(
    client: CoordinatorClient,
    current_worker_id: str,
    metadata: dict[str, Any],
    stop_event: threading.Event,
) -> None:
    while not stop_event.wait(15):
        try:
            client.request(
                "POST",
                f"/api/workers/{current_worker_id}/heartbeat",
                {"status": "busy", "metadata": metadata},
            )
        except Exception as error:
            print(f"Heartbeat fehlgeschlagen: {error}", flush=True)


def execute_job(
    client: CoordinatorClient,
    current_worker_id: str,
    job: dict[str, Any],
    metadata: dict[str, Any],
) -> tuple[bool, dict[str, Any], str | None]:
    global CURRENT_PROCESS

    command, env = job_command(job)
    started = time.monotonic()
    client.request(
        "POST",
        f"/api/jobs/{job['id']}/log",
        {"worker_id": current_worker_id, "text": f"$ {' '.join(command)}\n"},
    )
    popen_kwargs: dict[str, Any] = {
        "cwd": training_root(),
        "env": env,
        "text": True,
        "stdout": subprocess.PIPE,
        "stderr": subprocess.STDOUT,
        "bufsize": 1,
    }
    if not IS_WINDOWS:
        popen_kwargs["start_new_session"] = True
    process = subprocess.Popen(command, **popen_kwargs)
    with PROCESS_LOCK:
        CURRENT_PROCESS = process
    assert process.stdout is not None
    stop_event = threading.Event()
    heartbeat = threading.Thread(
        target=heartbeat_loop,
        args=(client, current_worker_id, metadata, stop_event),
        daemon=True,
        name=f"bittts-heartbeat-{job['id'][:8]}",
    )
    heartbeat.start()
    buffered: list[str] = []
    last_flush = time.monotonic()

    try:
        for line in process.stdout:
            print(line, end="", flush=True)
            buffered.append(line)
            now = time.monotonic()
            if len(buffered) >= 20 or now - last_flush >= 2:
                client.request(
                    "POST",
                    f"/api/jobs/{job['id']}/log",
                    {"worker_id": current_worker_id, "text": "".join(buffered)},
                )
                buffered.clear()
                last_flush = now
        returncode = process.wait()
    except BaseException:
        terminate_process(process)
        raise
    finally:
        stop_event.set()
        heartbeat.join(timeout=5)
        with PROCESS_LOCK:
            CURRENT_PROCESS = None

    if buffered:
        client.request(
            "POST",
            f"/api/jobs/{job['id']}/log",
            {"worker_id": current_worker_id, "text": "".join(buffered)},
        )
    duration = round(time.monotonic() - started, 2)
    result = {
        "returncode": returncode,
        "duration_seconds": duration,
        "worker": current_worker_id,
        "output_voice": env["BITTTS_OUTPUT_VOICE"],
        "dataset_profile": env.get("BITTTS_DATASET_PROFILE"),
        "speaker_id": env.get("BITTTS_SPEAKER_ID", ""),
    }
    if STOP_REQUESTED.is_set() and returncode != 0:
        error = "Worker wurde gestoppt."
    else:
        error = None if returncode == 0 else f"Prozess endete mit Exit-Code {returncode}"
    return returncode == 0, result, error


def run_worker(once: bool = False) -> int:
    coordinator_url = os.environ.get("BITTTS_COORDINATOR_URL", "").strip()
    token = os.environ.get("BITTTS_WORKER_TOKEN", "").strip()
    if not coordinator_url:
        raise RuntimeError("BITTTS_COORDINATOR_URL fehlt.")
    if len(token) < 24:
        raise RuntimeError("BITTTS_WORKER_TOKEN fehlt oder ist zu kurz.")

    bundle_root = ensure_training_bundle(coordinator_url, token)
    print(f"Training-Bundle: {bundle_root}", flush=True)

    current_worker_id = worker_id()
    name = os.environ.get("BITTTS_WORKER_NAME", "").strip() or socket.gethostname()
    poll_seconds = max(2, int(os.environ.get("BITTTS_WORKER_POLL_SECONDS", "5")))
    gpu, gpu_name = detect_gpu()
    capabilities = {
        "gpu": gpu,
        "actions": ["download", "prepare", "train", "full"],
        "profiles": ["mls-german", "thorsten-legacy"],
    }
    metadata = worker_metadata(gpu_name)
    client = CoordinatorClient(coordinator_url, token)

    registered = client.request(
        "POST",
        "/api/workers/register",
        {
            "worker_id": current_worker_id,
            "name": name,
            "capabilities": capabilities,
            "metadata": metadata,
        },
    )
    current_worker_id = registered["id"]
    print(f"Worker registriert: {name} ({current_worker_id})", flush=True)
    print(f"Worker-Runtime: {WORKER_RUNTIME_VERSION}", flush=True)
    print(f"Koordinator: {coordinator_url}", flush=True)
    print(f"GPU: {gpu_name}", flush=True)

    while not STOP_REQUESTED.is_set():
        try:
            client.request(
                "POST",
                f"/api/workers/{current_worker_id}/heartbeat",
                {"status": "idle", "metadata": metadata},
            )
            job = client.request(
                "POST",
                f"/api/workers/{current_worker_id}/claim",
                {"capabilities": capabilities},
            )
            if job:
                print(f"Job übernommen: {job['id']} ({job['action']})", flush=True)
                try:
                    success, result, error = execute_job(
                        client,
                        current_worker_id,
                        job,
                        metadata,
                    )
                except Exception as exc:
                    success, result, error = False, {}, str(exc)
                try:
                    client.request(
                        "POST",
                        f"/api/jobs/{job['id']}/complete",
                        {
                            "worker_id": current_worker_id,
                            "success": success,
                            "result": result,
                            "error": error,
                        },
                    )
                except Exception as exc:
                    print(f"Jobabschluss konnte nicht gemeldet werden: {exc}", flush=True)
                print(f"Job beendet: {job['id']} success={success}", flush=True)
                if once:
                    return 0 if success else 1
            elif once:
                print("Kein passender Job in der Queue.", flush=True)
                return 0
        except KeyboardInterrupt:
            STOP_REQUESTED.set()
        except Exception as exc:
            print(f"Worker-Verbindungsfehler: {exc}", flush=True)
            if once:
                return 1
        STOP_REQUESTED.wait(poll_seconds)

    return 0


def main() -> None:
    if not IS_WINDOWS:
        signal.signal(signal.SIGTERM, handle_signal)
    signal.signal(signal.SIGINT, handle_signal)
    parser = argparse.ArgumentParser(description="BKG BitTTS REST Worker")
    parser.add_argument("--once", action="store_true", help="Maximal einen Job bearbeiten")
    args = parser.parse_args()
    raise SystemExit(run_worker(once=args.once))


if __name__ == "__main__":
    main()
