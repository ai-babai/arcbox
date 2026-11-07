#!/bin/bash
set -euo pipefail
# Muter 16 launches builds with a minimal environment. Git needs an explicit PATH.
export PATH=/usr/bin:/bin:/usr/sbin:/sbin
SWIFT_BIN=${1:-/usr/bin/swift}
"$SWIFT_BIN" test
