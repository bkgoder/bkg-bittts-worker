# bkg-bittts-worker

GPU-Worker für [BKG BitTTS Trainer](https://github.com/bkgoder/bkg-bittts-trainer) — verbindet sich mit `https://train.eysho.info`, übernimmt Jobs und führt Trainingsskripte aus **bkg-bittts-shutup** aus.

## Repos

| Repo | Rolle |
|------|--------|
| **bkg-bittts-trainer** | Koordinator + Web-UI |
| **bkg-bittts-worker** (dieses) | Worker-Client |
| **bkg-bittts-shutup** | Trainingsskripte, Modelle |

## Windows (PowerShell)

Voraussetzungen:
- **Python 3.10+** (Microsoft Store, `winget install Python.Python.3.12`, oder python.org)
- **bkg-bittts-shutup** geklont
- Worker-Token aus https://train.eysho.info/ui

```powershell
git clone https://github.com/bkgoder/bkg-bittts-worker.git
cd bkg-bittts-worker

# .env bearbeiten: BITTTS_WORKER_TOKEN, BITTTS_SHUTUP_ROOT
notepad .env

.\scripts\win\install.ps1
.\scripts\win\start.ps1
.\scripts\win\status.ps1
.\scripts\win\connect.ps1   # Live-Log
.\scripts\win\stop.ps1
```

Für Trainingsskripte unter Windows: **Git Bash** oder **WSL** muss verfügbar sein (`bash` im PATH).

## Linux / WSL

```bash
git clone https://github.com/bkgoder/bkg-bittts-worker.git
cd bkg-bittts-worker
cp .env.example .env   # Token + BITTTS_SHUTUP_ROOT setzen

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
BITTTS_SHUTUP_ROOT=/pfad/zu/bkg-bittts-shutup
```

## Manuell (ohne Skripte)

```bash
python3 -m venv .venv
source .venv/bin/activate   # Windows: .venv\Scripts\Activate.ps1
pip install -e .
bkg-bittts-worker
```

## Colab

Notebook liegt im Trainer-Repo: `bkg-bittts-trainer/notebooks/`
