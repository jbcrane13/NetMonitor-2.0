#!/bin/bash
# #491 S5 macOS evidence: the dashboard health card with its history chart.
# Launches the Debug build (never /Applications/NetMonitor-macOS.app) with the UI-test arguments,
# seeds five health samples, and takes a window-only screenshot through scripts/ax/axdrive.swift.
# Usage: scripts/ax/health-history.sh <NetMonitor-macOS.app from DerivedData> <output dir>
set -euo pipefail
APP="$1"
OUT="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$OUT"
DRIVER="$OUT/axdrive"
swiftc -O -o "$DRIVER" "$HERE/axdrive.swift"

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-health-samples \
    > "$OUT/app.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

# The card's own id is stamped over by its container's (networkDetail_row_health).
for id in networkDetail_row_health healthGauge_chart_history; do
    result=$("$DRIVER" wait "$id" 40)
    echo "$result"
    [[ "$result" == found* ]] || { echo "FAIL: $id did not appear"; exit 1; }
done
echo "chart value: $("$DRIVER" value healthGauge_chart_history)"
sleep 2
"$DRIVER" capture "$OUT/macos-health-history.png"
