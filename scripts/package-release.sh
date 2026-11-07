#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh --universal
APP=dist/Arcbox.app
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
OUTPUT="$(pwd)/dist/release"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/arcbox-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
mkdir -p "$OUTPUT"
codesign --verify --deep --strict "$APP"
for binary in "$APP/Contents/MacOS/ArcboxDesktop" "$APP/Contents/MacOS/arcbox" "$APP/Contents/Resources/7zz"; do
  lipo "$binary" -verify_arch arm64 x86_64
done
ditto "$APP" "$STAGING/Arcbox.app"
ln -s /Applications "$STAGING/Applications"
cp docs/INSTALL.txt "$STAGING/Read me first.txt"
hdiutil create -volname Arcbox -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$OUTPUT/Arcbox-$VERSION-universal.dmg"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$OUTPUT/Arcbox-$VERSION-universal.zip"
VERSION="$VERSION" OUTPUT="$OUTPUT" python3 - <<'PY'
import json, os, pathlib, subprocess
result = {
    "version": os.environ["VERSION"], "architectures": ["arm64", "x86_64"],
    "minimumMacOS": "14.0", "signing": "ad-hoc", "notarized": False,
    "languages": ["en", "ru"],
    "engine": "7-Zip 26.05", "testedOn": "macOS 15.8.1, Apple Silicon",
    "intelRuntimeTested": False,
    "sourceCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
}
(pathlib.Path(os.environ["OUTPUT"]) / "release-info.json").write_text(json.dumps(result, indent=2) + "\n")
PY
(
  cd "$OUTPUT"
  shasum -a 256 "Arcbox-$VERSION-universal.dmg" "Arcbox-$VERSION-universal.zip" release-info.json > SHA256SUMS.txt
)
echo "Release assets: $OUTPUT"
