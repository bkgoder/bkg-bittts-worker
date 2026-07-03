from __future__ import annotations

import json
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

from worker.metrics import gpu_snapshot


class CoordinatorClient:
    def __init__(self, base_url: str, token: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.token = token

    def request(self, method: str, path: str, payload: dict[str, Any] | None = None) -> Any:
        outgoing = payload
        if payload and isinstance(payload.get("metadata"), dict):
            if path == "/api/workers/register" or path.endswith("/heartbeat"):
                outgoing = dict(payload)
                outgoing["metadata"] = {
                    **payload["metadata"],
                    **gpu_snapshot(),
                }

        data = None if outgoing is None else json.dumps(outgoing).encode("utf-8")
        request = Request(
            f"{self.base_url}{path}",
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Content-Type": "application/json",
                "User-Agent": "bkg-bittts-worker/0.5.3",
            },
        )
        try:
            with urlopen(request, timeout=60) as response:
                raw = response.read()
                return json.loads(raw.decode("utf-8")) if raw else None
        except HTTPError as error:
            body = error.read().decode("utf-8", errors="replace")
            if error.code == 401:
                raise RuntimeError(
                    "Koordinator HTTP 401: Worker-Token ungültig oder widerrufen. "
                    "Neuen Token unter https://train.eysho.info/ui erzeugen. "
                    f"Detail: {body}"
                ) from error
            raise RuntimeError(f"Koordinator HTTP {error.code}: {body}") from error
        except URLError as error:
            raise RuntimeError(f"Koordinator nicht erreichbar: {error}") from error
