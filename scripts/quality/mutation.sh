#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."

project_root=$PWD
lock_directory="$project_root/.build/mutation/lock"
run_directory=''
owns_lock=false

cleanup() {
  local status=$?
  if [[ -n "$run_directory" ]]; then
    rm -rf "$run_directory" || status=1
  fi
  if [[ "$owns_lock" == true ]]; then
    rmdir "$lock_directory" || status=1
  fi
  exit "$status"
}

prepare_workspace() {
  mkdir -p .build/mutation .build/quality
  if ! mkdir "$lock_directory" 2>/dev/null; then
    echo 'Another mutation run is active. Finish it before starting another gate.' >&2
    exit 1
  fi
  owns_lock=true
  run_directory=$(mktemp -d "$project_root/.build/mutation/run.XXXXXX")
  mkdir -p "$run_directory/project/vendor" "$run_directory/project/scripts/quality"
  cp -R Sources Tests Package.swift Package.resolved muter.conf.yml "$run_directory/project/"
  cp scripts/quality/mutation-tests.sh "$run_directory/project/scripts/quality/"
  python3 scripts/quality/mutation.py configure "$run_directory/project/muter.conf.yml" "$(xcrun --find swift)"
  cp -R vendor/7zip "$run_directory/project/vendor/"
}

run_mutations() {
  local report="$project_root/.build/quality/mutation.json"
  local log="$project_root/.build/quality/mutation.log"
  rm -f "$report"
  cd "$run_directory/project"
  if ! muter run \
    --files-to-mutate Sources/ArcboxCore/PartStream.swift \
    --files-to-mutate Sources/ArcboxCore/ArchivePathPolicy.swift \
    --operators RelationalOperatorReplacement ChangeLogicalConnector \
    --skip-update-check --skip-coverage --format json --output "$report" >"$log" 2>&1; then
    cat "$log" >&2
    return 1
  fi
  python3 "$project_root/scripts/quality/mutation.py" verify "$report" "$log"
}

main() {
  local installed
  installed=$(muter --version)
  if [[ "$installed" != 16 ]]; then
    echo 'Muter 16 required; run scripts/setup-quality.sh' >&2
    exit 1
  fi
  trap cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  prepare_workspace
  run_mutations
}

main "$@"
