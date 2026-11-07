"""Validate the localized key/printf contract without relying on the host language."""

import json
import re
import subprocess
from pathlib import Path


def catalog(language):
    path = Path("Sources/ArcboxCore/Resources") / f"{language}.lproj/Localizable.strings"
    result = subprocess.run(["plutil", "-convert", "json", "-o", "-", str(path)], check=True, capture_output=True)
    return json.loads(result.stdout)


def placeholders(text):
    return sorted(
        re.findall(r"%(?:[0-9]+\$)?[-+0 #]*(?:[0-9]+|\*)?(?:\.[0-9]+)?(?:ll|l|z)?[@diufsg]", text.replace("%%", ""))
    )


def main():
    english, russian = catalog("en"), catalog("ru")
    if english.keys() != russian.keys():
        raise ValueError(f"EN/RU key mismatch: {english.keys() ^ russian.keys()}")
    for key in english:
        if placeholders(english[key]) != placeholders(russian[key]):
            raise ValueError(f"EN/RU printf mismatch: {key}")
    print(f"EN/RU catalogs: {len(english)} matching keys and placeholders")


if __name__ == "__main__":
    main()
