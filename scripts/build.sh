#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" != "" ] && [ "${1:-}" != "--universal" ]; then
  echo 'Usage: ./scripts/build.sh [--universal]' >&2
  exit 2
fi
ENGINE_VERSION=26.05
ENGINE_SHA=12ef6830317743cfd3f0ab1724bde43fcc270d8b6d8564f8c12c2a2b7f993570
if [ ! -f vendor/7zip.tar.xz ]; then
  mkdir -p vendor
  curl -fL --retry 2 "https://github.com/ip7z/7zip/releases/download/$ENGINE_VERSION/7z2605-mac.tar.xz" -o vendor/7zip.tar.xz
fi
ACTUAL_SHA=$(shasum -a 256 vendor/7zip.tar.xz | cut -d ' ' -f 1)
if [ "$ACTUAL_SHA" != "$ENGINE_SHA" ]; then
  echo '7-Zip checksum mismatch' >&2
  exit 1
fi
mkdir -p vendor/7zip
tar -xJf vendor/7zip.tar.xz -C vendor/7zip
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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/7zip-license"
cp "$BINARY_DIR/ArcboxDesktop" "$BINARY_DIR/arcbox" "$APP/Contents/MacOS/"
cp vendor/7zip/7zz "$APP/Contents/Resources/7zz"
cp vendor/7zip/License.txt vendor/7zip/readme.txt "$APP/Contents/Resources/7zip-license/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp LICENSE "$APP/Contents/Resources/Arcbox-LICENSE.txt"
ditto "$RESOURCE_DIR/Arcbox_ArcboxCore.bundle" "$APP/Contents/Resources/Arcbox_ArcboxCore.bundle"
swift scripts/make-icon.swift "$APP/Contents/Resources/Arcbox.icns"
codesign --force --sign - "$APP/Contents/Resources/7zz"
codesign --force --sign - "$APP/Contents/MacOS/arcbox"
codesign --force --sign - "$APP"
ln -sfn Arcbox.app/Contents/MacOS/arcbox dist/arcbox
echo "Built: $(pwd)/$APP"
