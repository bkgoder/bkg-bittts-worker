from __future__ import annotations

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
