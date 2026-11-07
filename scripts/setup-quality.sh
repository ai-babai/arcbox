#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Tool versions are reviewed together with their quality configuration.
HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install swiftlint muter-mutation-testing/formulae/muter uv ripgrep
./scripts/fetch-complexity.sh
uv venv --allow-existing --python 3.12 .build/quality-venv
uv pip install --python .build/quality-venv/bin/python --require-hashes -r scripts/quality/requirements.txt
swift package resolve
# Preserve an existing custom hook path rather than replacing it silently.
CURRENT=$(git config --local --get core.hooksPath || true)
if [ -n "$CURRENT" ] && [ "$CURRENT" != .githooks ]; then
  echo "Existing core.hooksPath=$CURRENT; chain .githooks/pre-commit from your hook." >&2
  exit 1
fi
git config --local core.hooksPath .githooks
echo 'Quality tools and commit hook installed. Run ./scripts/quality.sh.'
