from __future__ import annotations

import os


def _apply_master_port_override() -> None:
    """Force worker slot port before torch.distributed initializes.

    Some bundled shell scripts still assign MASTER_PORT=65520 internally.
    In multi-worker mode every training process then fights for the same local
    c10d TCPStore port. get_job.sh exports BITTTS_MASTER_PORT per worker slot,
    so we re-apply it here at Python startup, before train_latest.py calls
    dist.init_process_group(env://).
    """

    desired = os.environ.get("BITTTS_MASTER_PORT", "").strip()
    if not desired or not desired.isdigit():
        return
    os.environ["MASTER_PORT"] = desired
    os.environ.setdefault("MASTER_ADDR", "127.0.0.1")


_apply_master_port_override()

try:
    import torch
except Exception:  # pragma: no cover - only active inside training runtime
    torch = None

if torch is not None and not getattr(torch.stft, "_bkg_return_complex_patched", False):
    _original_stft = torch.stft

    def _bkg_stft_return_complex_compat(*args, **kwargs):
        if "return_complex" not in kwargs:
            kwargs["return_complex"] = False
        return _original_stft(*args, **kwargs)

    _bkg_stft_return_complex_compat._bkg_return_complex_patched = True
    torch.stft = _bkg_stft_return_complex_compat

try:
    import librosa
except Exception:  # pragma: no cover - only active inside training runtime
    librosa = None

if librosa is not None:
    mel_fn = getattr(getattr(librosa, "filters", None), "mel", None)
    if mel_fn is not None and not getattr(mel_fn, "_bkg_positional_patched", False):
        _original_mel = mel_fn

        def _bkg_librosa_mel_compat(*args, **kwargs):
            if args:
                names = ["sr", "n_fft", "n_mels", "fmin", "fmax"]
                for name, value in zip(names, args):
                    kwargs.setdefault(name, value)
                args = args[len(names):]
            return _original_mel(*args, **kwargs)

        _bkg_librosa_mel_compat._bkg_positional_patched = True
        librosa.filters.mel = _bkg_librosa_mel_compat
