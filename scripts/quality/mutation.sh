#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
[ "$(muter --version)" = 16.0 ] || [ "$(muter --version)" = 16 ] || { echo 'Muter 16 required; run scripts/setup-quality.sh' >&2; exit 1; }
mkdir -p .build/mutation .build/quality
if ! mkdir .build/mutation/lock 2>/dev/null; then
  echo 'Another mutation run is active. Finish it before starting another gate.' >&2; exit 1
fi
# Fresh compiler caches: Muter copies its input and Swift PCHs cannot be moved.
LOCK="$PWD/.build/mutation/lock"
RUN=$(mktemp -d "$PWD/.build/mutation/run.XXXXXX")
trap 'rm -rf "$RUN"; rmdir "$LOCK"' EXIT
mkdir -p "$RUN/project/vendor" "$RUN/project/scripts/quality"
cp -R Sources Tests Package.swift Package.resolved muter.conf.yml "$RUN/project/"
cp scripts/quality/mutation-tests.sh "$RUN/project/scripts/quality/"
python3 - "$RUN/project/muter.conf.yml" "$(xcrun --find swift)" <<'PYTHON'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text().replace('  - scripts/quality/mutation-tests.sh',
                                '  - scripts/quality/mutation-tests.sh\n  - ' + json.dumps(sys.argv[2]))
path.write_text(text)
PYTHON
cp -R vendor/7zip "$RUN/project/vendor/"
REPORT="$PWD/.build/quality/mutation.json"
LOG="$PWD/.build/quality/mutation.log"
cd "$RUN/project"
muter run --files-to-mutate Sources/ArcboxCore/PartStream.swift --files-to-mutate Sources/ArcboxCore/ArchivePathPolicy.swift \
  --operators RelationalOperatorReplacement ChangeLogicalConnector \
  --skip-update-check --skip-coverage --format json --output "$REPORT" > "$LOG" 2>&1 || { cat "$LOG"; exit 1; }
# A compiler/environment failure is never a killed mutant.
if rg -q 'error: (fatalError|emit-module|compile command)|failed to compile|missing required module' "$LOG"; then
  cat "$LOG"; exit 1
fi
python3 - "$REPORT" <<'PY'
import json, sys
report = json.load(open(sys.argv[1]))
outcomes = [v['testSuiteOutcome'] for f in report['fileReports'] for v in f['appliedOperators']]
if not outcomes or any(v != 'failed' for v in outcomes):
    raise SystemExit(f'Mutation gate failed: {outcomes}; inspect .build/quality/mutation.json and mutation.log')
print(f'Scoped mutation check: {len(outcomes)}/{len(outcomes)} killed (stream boundaries, archive paths; two operators)')
PY
