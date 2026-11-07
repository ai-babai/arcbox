#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" != "" ] && [ "${1:-}" != "--universal" ]; then
  echo 'Usage: ./scripts/build.sh [--universal]' >&2
  exit 2
fi
./scripts/fetch-engine.sh
if [ "${1:-}" = "--universal" ]; then
  swift build -c release --triple arm64-apple-macosx14.0
  swift build -c release --triple x86_64-apple-macosx14.0
  mkdir -p dist/.universal
  for binary in ArcboxDesktop arcbox; do
    lipo -create ".build/arm64-apple-macosx/release/$binary" ".build/x86_64-apple-macosx/release/$binary" -output "dist/.universal/$binary"
  done
  BINARY_DIR=dist/.universal
  RESOURCE_DIR=.build/arm64-apple-macosx/release
else
  swift build -c release
  BINARY_DIR=$(swift build -c release --show-bin-path)
  RESOURCE_DIR="$BINARY_DIR"
fi
APP=dist/Arcbox.app
mkdir -p dist
STAGING=$(mktemp -d dist/.arcbox-build.XXXXXX)
trap 'rm -rf "$STAGING"' EXIT
BUILT_APP="$STAGING/Arcbox.app"
mkdir -p "$BUILT_APP/Contents/MacOS" "$BUILT_APP/Contents/Resources/7zip-license"
cp "$BINARY_DIR/ArcboxDesktop" "$BINARY_DIR/arcbox" "$BUILT_APP/Contents/MacOS/"
cp vendor/7zip/7zz "$BUILT_APP/Contents/Resources/7zz"
cp vendor/7zip/License.txt vendor/7zip/readme.txt "$BUILT_APP/Contents/Resources/7zip-license/"
cp Resources/Info.plist "$BUILT_APP/Contents/Info.plist"
cp LICENSE "$BUILT_APP/Contents/Resources/Arcbox-LICENSE.txt"
ditto "$RESOURCE_DIR/Arcbox_ArcboxCore.bundle" "$BUILT_APP/Contents/Resources/Arcbox_ArcboxCore.bundle"
swift scripts/make-icon.swift "$BUILT_APP/Contents/Resources/Arcbox.icns"
codesign --force --sign - "$BUILT_APP/Contents/Resources/7zz"
codesign --force --sign - "$BUILT_APP/Contents/MacOS/arcbox"
codesign --force --sign - "$BUILT_APP"
codesign --verify --deep --strict "$BUILT_APP"
if [[ -e "$APP" || -L "$APP" ]]; then
  mv "$APP" "$STAGING/previous.app"
fi
if ! mv "$BUILT_APP" "$APP"; then
  if [[ -e "$STAGING/previous.app" || -L "$STAGING/previous.app" ]]; then
    mv "$STAGING/previous.app" "$APP"
  fi
  exit 1
fi
ln -sfn Arcbox.app/Contents/MacOS/arcbox dist/arcbox
echo "Built: $(pwd)/$APP"
