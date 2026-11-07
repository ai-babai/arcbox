"""Exercise the public JSON/stdio contract through the compiled CLI."""

import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

CLI = str(Path(os.environ["ARCBOX_CLI"]).resolve())


class ProtocolTests(unittest.TestCase):
    def call(self, *arguments, stdin=None, status=0):
        process = subprocess.run([CLI, *map(str, arguments)], input=stdin, text=True, capture_output=True, timeout=30)
        self.assertEqual(process.returncode, status, process.stdout + process.stderr)
        return json.loads(process.stdout)

    def test_argument_errors_and_literal_paths(self):
        for arguments in [
            ("list",),
            ("create", "--level", "bad"),
            ("split", "x", "--part-bytes", "0"),
            ("list", "--unknown", "x"),
        ]:
            self.assertEqual(self.call(*arguments, status=2)["error"]["code"], "invalid_arguments")
        self.assertEqual(self.call("list", "--", "--definitely-missing", status=1)["error"]["code"], "file_missing")

    def test_cli_multipart_round_trip(self):
        with tempfile.TemporaryDirectory(prefix="arcbox-cli-") as directory:
            root = Path(directory)
            source = root / "данные.bin"
            data = bytes(range(256)) * 8
            source.write_bytes(data)
            created = self.call("create", source, "--output", root / "parts", "--format", "parts", "--part-bytes", 127)[
                "result"
            ]
            middle = Path(created["firstPart"]).with_suffix(".002")
            self.assertTrue(self.call("list", middle)["result"]["isFileParts"])
            self.call("extract", middle, "--to", root / "restored")
            self.assertEqual((root / "restored" / source.name).read_bytes(), data)
            self.assertEqual(source.read_bytes(), data)

    def test_password_stdin_round_trip(self):
        with tempfile.TemporaryDirectory(prefix="arcbox-cli-") as directory:
            root = Path(directory)
            source = root / "note"
            source.write_text("secret")
            self.call(
                "create",
                source,
                "--output",
                root / "secret.7z",
                "--format",
                "7z",
                "--password-stdin",
                stdin="test-password\n",
            )
            self.call("test", root / "secret.7z", "--password-stdin", stdin="test-password\n")
            self.assertEqual(
                self.call("test", root / "secret.7z", "--password-stdin", stdin="wrong\n", status=1)["error"]["code"],
                "password_required",
            )

    def test_mcp_negotiation_tools_and_errors(self):
        requests = [
            {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {"protocolVersion": "2025-06-18"}},
            {"jsonrpc": "2.0", "method": "notifications/initialized"},
            {"jsonrpc": "2.0", "id": 2, "method": "tools/list"},
            {"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "arcbox_missing"}},
            {"jsonrpc": "2.0", "id": 4, "method": "unknown"},
        ]
        process = subprocess.run(
            [CLI, "mcp"], input="\n".join(map(json.dumps, requests)) + "\n", text=True, capture_output=True, timeout=30
        )
        self.assertEqual(process.returncode, 0, process.stderr)
        responses = [json.loads(line) for line in process.stdout.splitlines()]
        self.assertEqual(len(responses), 4)
        self.assertEqual(responses[0]["result"]["protocolVersion"], "2025-06-18")
        self.assertEqual(len(responses[1]["result"]["tools"]), 6)
        self.assertTrue(responses[2]["result"]["isError"])
        self.assertEqual(responses[3]["error"]["code"], -32601)


if __name__ == "__main__":
    unittest.main()
