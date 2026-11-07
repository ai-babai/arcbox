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
  local tools=(swiftlint uv ripgrep shellcheck shfmt)
  if [[ "${1:-}" == --full ]]; then
    tools+=(muter-mutation-testing/formulae/muter)
  fi
  # Muter is needed only for an explicitly requested full check.
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 brew install \
    "${tools[@]}"
  ./scripts/fetch-complexity.sh
  uv venv --allow-existing --python 3.12 .build/quality-venv
  uv pip install --python .build/quality-venv/bin/python \
    --require-hashes -r scripts/quality/requirements.txt
}

main() {
  if [[ $# -gt 1 || ($# -eq 1 && "$1" != --full) ]]; then
    echo 'Usage: ./scripts/setup-quality.sh [--full]' >&2
    exit 2
  fi
  check_hook_path
  install_tools "$@"
  swift package resolve
  git config --local core.hooksPath .githooks
  echo 'Quality tools and commit hook installed. Run ./scripts/quality.sh.'
}

main "$@"
