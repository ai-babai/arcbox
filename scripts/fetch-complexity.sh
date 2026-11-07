#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
case "$(uname -m)" in
  arm64)
    ARCH=arm64
    SHA=a54d2731acacbe912bb42f61b81836fe3c18dbbed12469fb812436a0d3f10ffb
    ;;
  x86_64)
    ARCH=x86_64
    SHA=fd19138ed553188e2b4856af8f3e848355112b74f1094cfef60f9a1d46a3eafa
    ;;
  *)
    echo 'Unsupported macOS architecture' >&2
    exit 1
    ;;
esac
NAME="SwiftComplexityCLI-1.6.0-macos-$ARCH"
TOOLS=.build/quality-tools
if [ ! -x "$TOOLS/$NAME/SwiftComplexityCLI" ]; then
  mkdir -p "$TOOLS"
  ARCHIVE=$(mktemp)
  trap 'rm -f "$ARCHIVE"' EXIT
  curl -fL --retry 2 "https://github.com/fummicc1/swift-complexity/releases/download/v1.6.0/$NAME.tar.gz" -o "$ARCHIVE"
  ACTUAL=$(shasum -a 256 "$ARCHIVE" | cut -d ' ' -f 1)
  if [[ "$ACTUAL" != "$SHA" ]]; then
    echo 'Complexity analyzer checksum mismatch' >&2
    exit 1
  fi
  tar -xzf "$ARCHIVE" -C "$TOOLS"
fi
ln -sfn "$NAME/SwiftComplexityCLI" "$TOOLS/swift-complexity"
