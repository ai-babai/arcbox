"""Mutation reports must fail closed, and interrupted setup must release only its own lock."""

import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("mutation", Path("scripts/quality/mutation.py"))
mutation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mutation)
SCRIPT = Path("scripts/quality/mutation.sh").resolve()


class MutationToolTests(unittest.TestCase):
    def test_survivors_empty_reports_and_compiler_errors_fail(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            report, log = root / "report.json", root / "run.log"
            log.write_text("")
            with self.assertRaises(FileNotFoundError):
                mutation.verify(report, log)
            for outcomes in [[], ["passed"], ["timedOut"], ["failed", "passed"]]:
                report.write_text(
                    json.dumps(
                        {"fileReports": [{"appliedOperators": [{"testSuiteOutcome": item} for item in outcomes]}]}
                    )
                )
                with self.assertRaises(ValueError):
                    mutation.verify(report, log)
            report.write_text(json.dumps({"fileReports": [{"appliedOperators": [{"testSuiteOutcome": "failed"}]}]}))
            log.write_text("error: emit-module command failed")
            with self.assertRaises(ValueError):
                mutation.verify(report, log)
            log.write_text("")
            with contextlib.redirect_stdout(io.StringIO()):
                mutation.verify(report, log)

    def test_toolchain_path_is_serialized_as_one_yaml_argument(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "config.yml"
            path.write_text("arguments:\n  - scripts/quality/mutation-tests.sh\n")
            swift = '/Applications/Toolchain "A"/swift'
            mutation.configure(path, swift)
            self.assertEqual(json.loads(path.read_text().splitlines()[-1][4:]), swift)
            path.write_text("arguments: []\n")
            with self.assertRaises(ValueError):
                mutation.configure(path, swift)

    def test_setup_failure_releases_its_lock_and_workspace(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.prepare_script(directory)
            # No Sources/Tests: setup must fail without starting real mutation tests.
            result = self.run_script(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(list((root / ".build/mutation").iterdir()), [])

    def test_busy_lock_belongs_to_other_run(self):
        with tempfile.TemporaryDirectory() as directory:
            root = self.prepare_script(directory)
            lock = root / ".build/mutation/lock"
            lock.mkdir(parents=True)
            (lock / "owner").write_text("other run")
            result = self.run_script(root)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual((lock / "owner").read_text(), "other run")

    @staticmethod
    def prepare_script(directory):
        root = Path(directory)
        target = root / "scripts/quality/mutation.sh"
        target.parent.mkdir(parents=True)
        target.write_bytes(SCRIPT.read_bytes())
        target.chmod(0o755)
        binary = root / "bin/muter"
        binary.parent.mkdir()
        binary.write_text("#!/bin/sh\nprintf '16\\n'\n")
        binary.chmod(0o755)
        return root

    @staticmethod
    def run_script(root):
        environment = dict(os.environ, PATH=f"{root / 'bin'}:{os.environ['PATH']}")
        return subprocess.run(
            [str(root / "scripts/quality/mutation.sh")], env=environment, capture_output=True, timeout=10
        )
