"""Prepare Muter's selected toolchain and verify its declared report scope."""

import argparse
import json
from pathlib import Path
import re


def configure(path, swift):
    text = path.read_text()
    command = "  - scripts/quality/mutation-tests.sh"
    if text.count(command) != 1:
        raise ValueError("Expected one mutation test command in configuration")
    path.write_text(text.replace(command, command + "\n  - " + json.dumps(swift)))


def verify(report_path, log_path):
    log = log_path.read_text()
    if re.search(r"error: (fatalError|emit-module|compile command)|failed to compile|missing required module", log):
        raise ValueError("Mutation compilation/environment failure; inspect .build/quality/mutation.log")
    report = json.loads(report_path.read_text())
    outcomes = [value["testSuiteOutcome"] for file in report["fileReports"] for value in file["appliedOperators"]]
    if not outcomes or any(value != "failed" for value in outcomes):
        raise ValueError(f"Mutation gate failed: {outcomes}; inspect .build/quality/mutation.json and mutation.log")
    print(
        f"Scoped mutation check: {len(outcomes)}/{len(outcomes)} killed (stream boundaries, archive paths; two operators)"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    prepare = commands.add_parser("configure")
    prepare.add_argument("config", type=Path)
    prepare.add_argument("swift")
    check = commands.add_parser("verify")
    check.add_argument("report", type=Path)
    check.add_argument("log", type=Path)
    args = parser.parse_args()
    if args.command == "configure":
        configure(args.config, args.swift)
    else:
        verify(args.report, args.log)


if __name__ == "__main__":
    main()
