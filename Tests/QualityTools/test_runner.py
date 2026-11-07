"""The gate must propagate tool failures, preserve arguments and stop before later phases."""

import contextlib
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("gate", Path("scripts/quality/gate.py"))
gate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gate)


class RunnerTests(unittest.TestCase):
    def test_failed_command_stops_later_phases(self):
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "must-not-exist"
            phases = [
                ("fails", lambda: gate.run(sys.executable, "-c", "raise SystemExit(7)")),
                ("must not run", lambda: marker.write_text("wrong")),
            ]
            with contextlib.redirect_stdout(io.StringIO()), self.assertRaises(subprocess.CalledProcessError) as error:
                gate.execute_phases(phases)
            self.assertEqual(error.exception.returncode, 7)
            self.assertFalse(marker.exists())

    def test_arguments_are_passed_literally(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "file with spaces'$.txt"
            text = "literal $(command); 'text'"
            gate.run(
                sys.executable,
                "-c",
                "import pathlib,sys; pathlib.Path(sys.argv[1]).write_text(sys.argv[2])",
                output,
                text,
            )
            self.assertEqual(output.read_text(), text)

    def test_entrypoint_rejects_invalid_revision_and_options(self):
        for arguments, code in [(("--unknown",), 2), (("--base", "--help"), 2), (("--base=--help",), 1)]:
            result = subprocess.run(["./scripts/quality.sh", *arguments], capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, code, result.stdout + result.stderr)
            self.assertNotIn("Quality gate passed", result.stdout)

    def test_setup_preserves_custom_hook_before_installing_tools(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            subprocess.run(["git", "init", "-q", str(root)], check=True)
            subprocess.run(["git", "config", "--local", "core.hooksPath", "custom-hooks"], cwd=root, check=True)
            target = root / "scripts/setup-quality.sh"
            target.parent.mkdir()
            target.write_bytes(Path("scripts/setup-quality.sh").read_bytes())
            result = subprocess.run(["/bin/bash", str(target)], text=True, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 1)
            self.assertIn("Existing core.hooksPath=custom-hooks", result.stderr)
            self.assertNotIn("brew", result.stderr)

    def test_release_metadata_preserves_public_contract(self):
        with tempfile.TemporaryDirectory() as directory:
            gate.run(sys.executable, "scripts/release-info.py", "0.2.3", directory)
            metadata = json.loads((Path(directory) / "release-info.json").read_text())
            self.assertEqual(metadata["version"], "0.2.3")
            self.assertEqual(metadata["architectures"], ["arm64", "x86_64"])
            self.assertFalse(metadata["notarized"])
            self.assertEqual(metadata["signing"], "ad-hoc")
            self.assertEqual(metadata["sourceCommit"], gate.capture("git", "rev-parse", "HEAD"))
