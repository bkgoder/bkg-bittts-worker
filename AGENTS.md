# BKG BitTTS Worker

This repo contains the GPU worker client for the BKG BitTTS trainer.

## Rules

- Keep worker code separate from trainer engine code.
- Training scripts are downloaded from the trainer coordinator bundle.
- Do not commit secrets from `.env`, worker tokens, Paperspace tokens, or Hugging Face tokens.
- Use feature branches for changes and open a PR to `main`.

## Verification

Before proposing a worker change, run focused checks for the touched area. For bundle/bootstrap changes, run:

```bash
python3 -m py_compile worker/bootstrap.py worker/main.py
python3 -m unittest discover
```
