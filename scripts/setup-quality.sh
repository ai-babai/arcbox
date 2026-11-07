#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

check_hook_path() {
  local current
  current=$(git config --local --get core.hooksPath || true)
  if [[ -n "$current" && "$current" != .githooks ]]; then
    echo "Existing core.hooksPath=$current; chain .githooks/pre-commit from your hook." >&2
    exit 1
  fi
}

install_tools() {
  # Versions are checked by the gate and reviewed with their configurations.
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install \
    swiftlint muter-mutation-testing/formulae/muter uv ripgrep shellcheck shfmt
  ./scripts/fetch-complexity.sh
  uv venv --allow-existing --python 3.12 .build/quality-venv
  uv pip install --python .build/quality-venv/bin/python \
    --require-hashes -r scripts/quality/requirements.txt
}

main() {
  check_hook_path
  install_tools
  swift package resolve
  git config --local core.hooksPath .githooks
  echo 'Quality tools and commit hook installed. Run ./scripts/quality.sh.'
}

main "$@"
