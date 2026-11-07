#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
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
