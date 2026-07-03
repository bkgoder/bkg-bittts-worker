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
