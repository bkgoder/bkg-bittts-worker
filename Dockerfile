# CUDA + Build-Tools für monotonic_align (Cython). Lokal: docker compose up
FROM pytorch/pytorch:2.5.1-cuda12.4-cudnn9-devel

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    BITTTS_WORKER_RUNTIME=/runtime \
    BITTTS_BUNDLE_DIR=/runtime/bundle \
    BITTTS_WORKER_DATASET=/data/mls-german

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        espeak-ng \
        ffmpeg \
        git \
        libsndfile1 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY requirements-gpu.txt pyproject.toml README.md ./
COPY worker ./worker
COPY docker/entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh \
    && python -m pip install --upgrade pip wheel setuptools \
    && python -m pip install -r requirements-gpu.txt \
    && python -m pip install -e .

RUN mkdir -p /runtime /data \
    && git config --system --add safe.directory '*'

VOLUME ["/runtime", "/data"]

HEALTHCHECK --interval=60s --timeout=15s --start-period=30s --retries=3 \
    CMD python -c "import torch; raise SystemExit(0 if torch.cuda.is_available() else 1)"

ENTRYPOINT ["/entrypoint.sh"]
CMD []
