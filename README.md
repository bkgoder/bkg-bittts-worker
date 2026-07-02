# bkg-bittts-worker

GPU-Worker für [BKG BitTTS Trainer](https://github.com/bkgoder/bkg-bittts-trainer) — verbindet sich mit `https://train.eysho.info`, lädt Trainingsskripte automatisch per Bootstrap und führt Jobs aus.

## Repos

| Repo | Rolle |
|------|--------|
| **bkg-bittts-trainer** | Koordinator + Web-UI |
| **bkg-bittts-worker** (dieses) | Worker-Client |
| **bkg-bittts-shutup** | Trainingsskripte (vom Koordinator als ZIP) |

**Kein separates shutup-Clone nötig** — der Worker holt `mls-voice-trainer.sh` inkl. Upstream-Patches (scipy, monotonic_align, Colab-Buckets) vom Koordinator.

## Windows (PowerShell)

Voraussetzungen:
- **Python 3.10+**
- **Git Bash** oder **WSL** (`bash` im PATH)
- Worker-Token aus https://train.eysho.info/ui

```powershell
git clone https://github.com/bkgoder/bkg-bittts-worker.git
cd bkg-bittts-worker
cp .env.example .env   # BITTTS_WORKER_TOKEN eintragen

.\scripts\win\install.ps1
.\scripts\win\start.ps1
.\scripts\win\status.ps1
.\scripts\win\connect.ps1   # Live-Log
.\scripts\win\stop.ps1
```

## Linux / WSL

```bash
git clone https://github.com/bkgoder/bkg-bittts-worker.git
cd bkg-bittts-worker
cp .env.example .env   # BITTTS_WORKER_TOKEN eintragen

bash scripts/linux/install.sh
bash scripts/linux/start.sh
bash scripts/linux/status.sh
bash scripts/linux/stop.sh
```

## .env (wichtig)

```env
BITTTS_COORDINATOR_URL=https://train.eysho.info
BITTTS_WORKER_TOKEN=bttw_...
BITTTS_WORKER_NAME=mein-pc
BITTTS_DATASET_SPLIT=9_hours
BITTTS_MAX_HOURS=9.0
```

Optional für lokale Entwicklung: `BITTTS_SHUTUP_ROOT=/pfad/zu/bkg-bittts-shutup`

Nach Koordinator-Updates Bundle erneuern:

```bash
BITTTS_BUNDLE_FORCE=1 bkg-bittts-worker --once
# oder: rm -rf runtime/bundle
```

## Manuell (ohne Skripte)

```bash
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\Activate.ps1
pip install -e .
bkg-bittts-worker
```

## Colab

Notebook: [bkg-bittts-trainer/notebooks/](https://github.com/bkgoder/bkg-bittts-trainer/tree/main/notebooks)
