"""Write release metadata beside the packaged macOS downloads."""

import argparse
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    result = {
        "version": args.version,
        "architectures": ["arm64", "x86_64"],
        "minimumMacOS": "14.0",
        "signing": "ad-hoc",
        "notarized": False,
        "languages": ["en", "ru"],
        "engine": "7-Zip 26.05",
        "testedOn": "macOS 15.8.1, Apple Silicon",
        "intelRuntimeTested": False,
        "sourceCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    }
    (args.output / "release-info.json").write_text(json.dumps(result, indent=2) + "\n")


if __name__ == "__main__":
    main()
