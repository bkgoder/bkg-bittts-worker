from __future__ import annotations

import subprocess
from typing import Any


def _number(value: str, cast: type[int] | type[float]) -> int | float | None:
    cleaned = value.strip().replace("[N/A]", "").replace("N/A", "")
    if not cleaned:
        return None
    try:
        return cast(float(cleaned)) if cast is int else cast(cleaned)
    except (TypeError, ValueError):
        return None


def gpu_snapshot() -> dict[str, Any]:
    """Return one compact NVIDIA GPU snapshot for coordinator heartbeats."""
    query = (
        "name,memory.total,memory.used,utilization.gpu,"
        "utilization.memory,temperature.gpu,power.draw"
    )
    try:
        result = subprocess.run(
            [
                "nvidia-smi",
                f"--query-gpu={query}",
                "--format=csv,noheader,nounits",
            ],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=8,
            check=False,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return {}

    line = next((item.strip() for item in result.stdout.splitlines() if item.strip()), "")
    if result.returncode != 0 or not line:
        return {}

    fields = [item.strip() for item in line.split(",")]
    if len(fields) < 7:
        return {}

    total = _number(fields[1], int)
    used = _number(fields[2], int)
    memory_percent = None
    if isinstance(total, int) and total > 0 and isinstance(used, int):
        memory_percent = round(used * 100 / total, 1)

    return {
        "gpu_name": fields[0],
        "gpu_memory_total_mib": total,
        "gpu_memory_used_mib": used,
        "gpu_memory_percent": memory_percent,
        "gpu_utilization_percent": _number(fields[3], int),
        "gpu_memory_utilization_percent": _number(fields[4], int),
        "gpu_temperature_c": _number(fields[5], int),
        "gpu_power_w": _number(fields[6], float),
    }
