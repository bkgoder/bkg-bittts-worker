# BKG BitTTS Worker

GPU-Worker für den zentralen Trainer unter `https://train.eysho.info`.

Der Worker-Code kommt ausschließlich aus diesem Repo. Der Trainer überschreibt ihn nicht. Trainingsskripte werden separat über `/api/worker/training-bundle` geladen und danach lokal behalten.

## Paperspace / JupyterLab ohne Docker

Im Notebook-Terminal:

```bash
git clone https://github.com/bkgoder/bkg-bittts-worker.git
cd bkg-bittts-worker
chmod +x get_home.sh get_job.sh
```

Einmalig mit dem Trainer verbinden:

```bash
./get_home.sh 'bttw_DEIN_TOKEN' paperspace-gpu-01
```

Worker im Vordergrund starten:

```bash
./get_job.sh
```

Nur genau einen Job übernehmen:

```bash
./get_job.sh --once
```

Nach einem Repo-Update:

```bash
git pull --ff-only
./get_job.sh
```

`get_job.sh` erstellt eine lokale `.venv`, verwendet die vorhandene Paperspace-CUDA-/PyTorch-Installation und installiert eine feste kompatible Hugging-Face-Kombination:

- `datasets==3.2.0`
- `huggingface_hub==0.27.1`
- `fsspec==2024.9.0`

Damit wird der bekannte `KeyError: 'maxdepth'` verhindert.

## Bootstrap-Verhalten

- `/api/worker/bootstrap`: Quellstand dieses Worker-Repos
- `/api/worker/training-bundle`: Trainings-Engine
- vorhandenes Trainings-Bundle bleibt unverändert
- bewusstes Update nur mit:

```bash
BITTTS_BUNDLE_FORCE=1 ./get_job.sh
```

Ein lokales Trainingsrepo kann stattdessen direkt verwendet werden:

```dotenv
BITTTS_SHUTUP_ROOT=/pfad/zu/bkg-bittts-shutup
```

## Docker / WSL

```bash
cp .env.example .env
# Token und Workername eintragen
docker compose up -d --build
docker compose logs -f worker
```

Der Docker-Worker verwendet dieselben festen Abhängigkeiten und denselben Queue-Client wie Paperspace.

## Klassische Linux-Skripte

```bash
bash scripts/linux/install.sh
bash scripts/linux/start.sh
bash scripts/linux/status.sh
bash scripts/linux/stop.sh
```

## Verbindung

```dotenv
BITTTS_COORDINATOR_URL=https://train.eysho.info
BITTTS_WORKER_TOKEN=bttw_DEIN_TOKEN
BITTTS_WORKER_NAME=paperspace-gpu-01
BITTTS_DATASET_SPLIT=9_hours
BITTTS_MAX_HOURS=9.0
```
