from __future__ import annotations

import io
import os
import shutil
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest import mock

from worker import bootstrap


ROOT = Path(__file__).resolve().parents[1]


class BundleForceTests(unittest.TestCase):
    def test_get_job_cli_force_overrides_dotenv_default(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            temp_root = Path(tmp)
            script = temp_root / "get_job.sh"
            shutil.copy2(ROOT / "get_job.sh", script)
            script.chmod(0o755)
            (temp_root / ".env").write_text(
                "\n".join(
                    [
                        "BITTTS_COORDINATOR_URL=https://train.eysho.info",
                        "BITTTS_WORKER_TOKEN=bttw_" + ("x" * 32),
                        "BITTTS_BUNDLE_FORCE=0",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            env = os.environ.copy()
            env["BITTTS_BUNDLE_FORCE"] = "1"
            env["BITTTS_GET_JOB_ENV_DRY_RUN"] = "1"
            result = subprocess.run(
                ["bash", str(script)],
                cwd=temp_root,
                env=env,
                text=True,
                capture_output=True,
                check=False,
            )

        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertIn("BITTTS_BUNDLE_FORCE=1", result.stdout)

    def test_bootstrap_env_force_refreshes_existing_bundle(self) -> None:
        payload = io.BytesIO()
        with zipfile.ZipFile(payload, mode="w") as archive:
            archive.writestr("scripts/mls-voice-trainer.sh", "#!/usr/bin/env bash\n")
            archive.writestr("worker-bundle.json", '{"files":["scripts/mls-voice-trainer.sh"]}\n')

        class Response:
            headers = {"X-BitTTS-Bundle-SHA256": "forced-refresh"}

            def __enter__(self) -> "Response":
                return self

            def __exit__(self, *args: object) -> None:
                return None

            def read(self) -> bytes:
                return payload.getvalue()

        with tempfile.TemporaryDirectory() as tmp:
            bundle_dir = Path(tmp) / "bundle"
            (bundle_dir / "scripts").mkdir(parents=True)
            (bundle_dir / "scripts" / "mls-voice-trainer.sh").write_text(
                "#!/usr/bin/env bash\n",
                encoding="utf-8",
            )
            (bundle_dir / ".bundle-sha256").write_text("old\n", encoding="utf-8")

            with (
                mock.patch.dict(os.environ, {"BITTTS_BUNDLE_FORCE": "1"}, clear=False),
                mock.patch.object(bootstrap, "BUNDLE_DIR", bundle_dir),
                mock.patch.object(bootstrap, "DIGEST_FILE", bundle_dir / ".bundle-sha256"),
                mock.patch.object(bootstrap, "MANIFEST_FILE", bundle_dir / "worker-bundle.json"),
                mock.patch.object(bootstrap, "urlopen", return_value=Response()) as urlopen,
            ):
                root = bootstrap.ensure_training_bundle(
                    "https://train.eysho.info",
                    "bttw_" + ("x" * 32),
                )

        self.assertEqual(root, bundle_dir)
        urlopen.assert_called_once()


if __name__ == "__main__":
    unittest.main()
