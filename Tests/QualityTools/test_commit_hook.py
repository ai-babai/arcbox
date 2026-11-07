"""A commit must contain the exact source tree validated by its hook."""

from pathlib import Path
import subprocess
import tempfile
import unittest

HOOK = Path(".githooks/pre-commit").resolve()


class CommitHookTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="arcbox-hook-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.git("init", "-q")
        (self.root / "source").write_text("original\n")
        (self.root / "scripts").mkdir()
        self.gate("exit 0")
        self.git("add", ".")

    def git(self, *arguments):
        return subprocess.run(["git", *arguments], cwd=self.root, check=True, capture_output=True)

    def gate(self, body):
        script = self.root / "scripts/quality.sh"
        script.write_text("#!/bin/bash\nset -eu\n" + body + "\n")
        script.chmod(0o755)

    def run_hook(self):
        return subprocess.run([str(HOOK)], cwd=self.root, text=True, capture_output=True, timeout=10)

    def test_clean_staged_tree_passes(self):
        self.assertEqual(self.run_hook().returncode, 0)

    def test_untracked_or_unstaged_work_blocks_commit(self):
        (self.root / "extra").write_text("untracked")
        self.assertNotEqual(self.run_hook().returncode, 0)
        (self.root / "extra").unlink()
        (self.root / "source").write_text("unstaged\n")
        self.assertNotEqual(self.run_hook().returncode, 0)

    def test_editing_source_during_validation_blocks_commit(self):
        self.gate("printf 'changed' > source")
        self.git("add", ".")
        self.assertNotEqual(self.run_hook().returncode, 0)

    def test_restaging_source_during_validation_blocks_commit(self):
        self.gate("printf 'changed' > source\ngit add source")
        self.git("add", ".")
        self.assertIn("staging area changed", self.run_hook().stderr)
