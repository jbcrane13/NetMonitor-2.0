#!/bin/zsh
# #628 PR A user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1).
# Launches a Debug build with UI-test arguments: the seeded uitest-device and a fixture scan that
# finds it and uitest-printer. UITEST_SCAN_PATH_CHANGE=1 simulates a network path change while the
# first scan runs. That scan must be dropped (no printer row, "Scan dropped" in the log), and the one
# replacement scan, started once the path is quiet (2 s), must save the printer.
# Screenshots are the app window cropped to the device cards: fixture devices only, no WAN or DNS.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/628-path-change-scan.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/628-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

UITEST_SCAN_PATH_CHANGE=1 \
  "$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-test-device \
  > "$OUT/app.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID
START=$(date '+%Y-%m-%d %H:%M:%S')

fail() { echo "FAIL: $1"; exit 1; }
expect() { [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

SEED=devices_card_192.168.77.77
PRINTER=devices_card_192.168.77.20

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
# The sidebar may start collapsed in a narrow window: widen it and open the sidebar.
if [[ "$("$AX" wait sidebar_nav_devices 3)" != found* ]]; then
  "$AX" resize 1400 900 > /dev/null
  "$AX" clickat main-AppWindow-1 113 26 > /dev/null
  expect "$("$AX" wait sidebar_nav_devices 5)" found "the sidebar never opened"
fi
"$AX" click sidebar_nav_devices > /dev/null
expect "$("$AX" wait $SEED 15)" found "the seeded device's card never showed"

# Scan 1: the path changes while it runs. The fixture scan finishes at once; check before the
# replacement's 2 s quiet period ends that the printer wasn't saved.
"$AX" menu "Scan Network"
sleep 0.8
expect "$("$AX" wait $PRINTER 0.5)" TIMEOUT "scan 1 saved the printer although the path changed while it ran"
"$AX" capture-union "$OUT/628-1-dropped.png" $SEED

# The replacement scan saves it.
expect "$("$AX" wait $PRINTER 15)" found "the replacement scan never saved the printer"
expect "$("$AX" textin $PRINTER Online 5)" "found text" "the printer's card doesn't say Online"
"$AX" capture-union "$OUT/628-2-replacement-saved.png" $SEED $PRINTER

# /usr/bin/log: zsh has a `log` builtin.
LOGS=$(/usr/bin/log show --start "$START" --predicate "processIdentifier == $PID AND category == 'discovery'" --style compact 2>/dev/null)
DROPS=$(print -r -- "$LOGS" | grep -c "Scan dropped" || true)
REPLACED=$(print -r -- "$LOGS" | grep -c "Scan started (replacement)" || true)
[[ $DROPS -eq 1 ]] || fail "expected one 'Scan dropped' in the app's log (got $DROPS)"
[[ $REPLACED -eq 1 ]] || fail "expected one replacement scan (got $REPLACED)"
echo "log: $DROPS dropped scan, $REPLACED replacement"
echo PASS
