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
python3 scripts/release-info.py "$VERSION" "$OUTPUT"

(
  cd "$OUTPUT"
  shasum -a 256 "Arcbox-$VERSION-universal.dmg" "Arcbox-$VERSION-universal.zip" release-info.json >SHA256SUMS.txt
)
echo "Release assets: $OUTPUT"
