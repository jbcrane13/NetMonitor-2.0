#!/bin/zsh
# #596 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1).
# Launches a Debug build with UI-test arguments: the seeded uitest-device, a fixture scan that
# finds it and uitest-printer, and two seams. UITEST_SCAN_CLOCK=1 steps each scan 10 minutes on;
# UITEST_SCAN_DROP_LAST=1 makes scans after the first miss the printer. With the grace policy
# (3 missed scans and 15 minutes) the printer's card must say Online after the first, second and
# third scans, and Offline only after the fourth (3 misses, 30 minutes). Screenshots are the
# app window cropped to the two device cards: fixture devices only, no WAN or DNS.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/596-offline-grace.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/596-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

UITEST_SCAN_CLOCK=1 UITEST_SCAN_DROP_LAST=1 \
  "$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-test-device \
  > "$OUT/app.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

fail() { echo "FAIL: $1"; exit 1; }
expect() { [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

PRINTER=devices_card_192.168.77.20
# Both cards: macOS 27 stamps a card's identifier on its parts, so crop to all of them.
CARDS=(devices_card_192.168.77.77 $PRINTER)

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
"$AX" click sidebar_nav_devices > /dev/null
expect "$("$AX" wait devices_card_192.168.77.77 15)" found "the seeded device's card never showed"

scan() {
  "$AX" menu "Scan Network"
  # The fixture scan finishes at once; give the store and the list a moment.
  sleep 3
}

# Scan 1: the printer answers and gets its card.
scan
expect "$("$AX" wait $PRINTER 15)" found "scan 1: the printer's card never showed"
expect "$("$AX" text Online 5)" "found text" "scan 1: no Online status"
"$AX" capture-union "$OUT/596-1-scan1-online.png" $CARDS

# Scans 2 and 3 miss it: within grace, so it stays Online (no Offline anywhere).
for n in 2 3; do
  scan
  expect "$("$AX" wait $PRINTER 5)" found "scan $n: the printer's card is gone"
  expect "$("$AX" notext Offline 5)" "no text" "scan $n: the printer went offline before grace"
done
"$AX" capture-union "$OUT/596-2-scan3-still-online.png" $CARDS

# Scan 4: the third miss, 30 minutes after it was seen: now Offline.
scan
expect "$("$AX" text Offline 10)" "found text" "scan 4: the printer never went offline"
"$AX" capture-union "$OUT/596-3-scan4-offline.png" $CARDS
echo PASS
