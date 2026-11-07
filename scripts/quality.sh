#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BASE=origin/main
if [ "${1:-}" = --base ] && [ "$#" -eq 2 ]; then BASE=$2
elif [ "$#" -ne 0 ]; then echo 'Usage: ./scripts/quality.sh [--base REVISION]' >&2; exit 2; fi
git rev-parse --verify "$BASE^{commit}" >/dev/null
mkdir -p .build/quality
command -v swiftlint >/dev/null || { echo 'Run ./scripts/setup-quality.sh' >&2; exit 1; }
[ "$(swiftlint version)" = 0.65.1 ] || { echo 'SwiftLint 0.65.1 required' >&2; exit 1; }
[ -x .build/quality-venv/bin/diff-cover ] && [ -x .build/quality-tools/swift-complexity ] || { echo 'Run ./scripts/setup-quality.sh' >&2; exit 1; }
# The pinned formatter is supplied by the Swift 6.1.2 / Xcode 16.4 toolchain.
swift --version | rg -q 'Swift version 6.1.2' || { echo 'Select Xcode 16.4 (Swift 6.1.2)' >&2; exit 1; }
echo '→ Formatting, lint and module boundaries'
xcrun swift-format lint --strict --recursive Sources Tests Package.swift
swiftlint lint --strict --quiet
.build/quality-venv/bin/ruff check scripts/quality Tests/QualityTools Tests/CLI
.build/quality-venv/bin/ruff format --check scripts/quality Tests/QualityTools Tests/CLI
python3 scripts/quality/architecture.py
python3 scripts/quality/catalogs.py
python3 -m unittest discover -s Tests/QualityTools -v
# Suppressions require a policy change; silently skipping a difficult function is not allowed.
if rg -n 'swift-complexity:disable|swiftlint:disable' Sources Tests --glob '*.swift'; then
  echo 'Inline quality suppressions are not allowed. Refactor or propose a documented policy change.' >&2; exit 1
fi
echo '→ Compiling both adapters and testing core behavior'
./scripts/fetch-engine.sh
swift build
ARCBOX_CLI="$(swift build --show-bin-path)/arcbox" python3 -m unittest discover -s Tests/CLI -v
swift test --enable-code-coverage
BIN=$(swift build --show-bin-path)
cp "$BIN/codecov/Arcbox.json" .build/quality/coverage.json
xcrun llvm-cov export -format=lcov -instr-profile "$BIN/codecov/default.profdata" \
  "$BIN/ArcboxPackageTests.xctest/Contents/MacOS/ArcboxPackageTests" > .build/quality/coverage.lcov
# Threshold 0 requests every function; the adapter below enforces distinct 10/15 limits.
STATUS=0
.build/quality-tools/swift-complexity Sources --recursive --format json --threshold 0 > .build/quality/complexity.json || STATUS=$?
[ "$STATUS" -le 1 ] || exit "$STATUS"
python3 scripts/quality/metrics.py
.build/quality-venv/bin/diff-cover .build/quality/coverage.xml --compare-branch "$BASE" --fail-under 80 \
  --format json:.build/quality/diff-coverage.json --format html:.build/quality/diff-coverage.html
echo '→ Mutation testing (stream boundaries and archive paths)'
./scripts/quality/mutation.sh
echo 'Quality gate passed. Reports: .build/quality/'
