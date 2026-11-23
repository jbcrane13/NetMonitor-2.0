#!/bin/zsh
# #491 S2 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1).
# Launches a Debug build with UI-test arguments, presses Scan Network, and checks the event
# recorder's file for "Scan Complete" and "Device Joined: uitest-printer" with a network ID.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/s2-scan-events.sh <Debug NetMonitor-macOS.app> <out-dir>
set -u
APP=$1
OUT=$2
mkdir -p $OUT
AX=$OUT/axdrive
swiftc -O ${0:A:h}/axdrive.swift -o $AX 2>/dev/null || { echo "driver build failed"; exit 1; }
EVENTS=${TMPDIR:-$(getconf DARWIN_USER_TEMP_DIR)}/netmonitor-uitest-history/network-events.json

$APP/Contents/MacOS/NetMonitor-macOS --uitesting --in-memory-store --reset-history-files --seed-test-device \
  > $OUT/app.log 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null' EXIT
export AX_PID=$PID

$AX wait networkDetail_section_devices 30
sleep 2
$AX menu "Scan Network" || exit 1

# The store writes a second after a change; wait for both events.
for _ in {1..30}; do
  grep -q 'Device Joined: uitest-printer' $EVENTS 2>/dev/null && grep -q 'Scan Complete' $EVENTS && break
  sleep 1
done
sleep 1
$AX capture $OUT/s2-dashboard-after-scan.png
cp $EVENTS $OUT/network-events.json
/usr/bin/python3 - $OUT/network-events.json <<'PY'
import json, sys
events = json.load(open(sys.argv[1]))
for e in events:
    print(f"{e['type']:<14} {e['title']:<36} networkProfileID={e.get('networkProfileID')} deviceID={e.get('deviceID')}")
titles = [e['title'] for e in events]
ok = any(t.startswith('Scan Complete') for t in titles) and 'Device Joined: uitest-printer' in titles \
    and all(e.get('networkProfileID') for e in events)
print('PASS' if ok else 'FAIL')
sys.exit(0 if ok else 1)
PY
