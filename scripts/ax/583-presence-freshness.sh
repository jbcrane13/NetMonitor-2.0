#!/bin/zsh
# #583 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1): online, offline and
# not checked recently, with relative last-seen times, and "Show past devices", in the device
# cards and the Pro mode table.
#
# Run 1: the seeded uitest-device, a fixture scan that also finds uitest-printer, and a past
# device (uitest-old-tv, offline, last seen 8 days ago). UITEST_SCAN_CLOCK=1 steps each scan
# 10 minutes on; UITEST_SCAN_DROP_LAST=1 makes scans after the first miss the printer. After four
# scans the printer is Offline (grace met) and the seeded device Online; the TV stays hidden until
# "Show past devices (1)" is pressed.
# Run 2: the same in the Pro mode table.
# Run 3: UITEST_PRESENCE_OFFSET=3600 shows presence an hour after the one scan, so every row reads
# "Not checked recently", whatever its saved status.
# Screenshots are the app window cropped to the device rows: fixture devices only, no WAN or DNS.
# Never touches an installed /Applications copy: it drives only the processes it started.
# Usage: scripts/ax/583-presence-freshness.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/583-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

fail() { echo "FAIL: $1"; exit 1; }
expect() { [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

SEEDED=192.168.77.77
PRINTER=192.168.77.20
TV=192.168.77.50

# launch <run> <Consumer|Pro>: the view mode comes from the argument domain, which is read but never
# saved, so the run never changes the user's own setting.
launch() {
  "$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files \
    --seed-test-device --seed-past-device -netmonitor.devices.viewMode "$2" > "$OUT/app-$1.log" 2>&1 &
  PID=$!
  export AX_PID=$PID
  expect "$("$AX" wait networkDetail_section_devices 40)" found "run $1: the dashboard never appeared"
  "$AX" click sidebar_nav_devices > /dev/null
}

quit() {
  kill $PID 2>/dev/null || true
  wait $PID 2>/dev/null || true
  sleep 2
}

scan() {
  "$AX" menu "Scan Network"
  # The fixture scan finishes at once; give the store and the list a moment.
  sleep 3
}

# MARK: Run 1: online, offline, past devices

UITEST_SCAN_CLOCK=1 UITEST_SCAN_DROP_LAST=1 launch 1 Consumer
trap 'kill $PID 2>/dev/null || true' EXIT
expect "$("$AX" wait devices_card_$SEEDED 15)" found "run 1: the seeded device's card never showed"

for n in 1 2 3 4; do scan; done
expect "$("$AX" textin devices_card_$SEEDED "Online" 5)" "found text" "the seeded device should be Online"
expect "$("$AX" textin devices_card_$SEEDED "Last seen just now" 5)" "found text" "the seeded device's last seen"
expect "$("$AX" textin devices_card_$PRINTER "Offline" 10)" "found text" "the printer should be Offline after grace"
expect "$("$AX" textin devices_card_$PRINTER "Last seen 30 min ago" 5)" "found text" "the printer's last seen"
expect "$("$AX" gone devices_card_$TV 3)" gone "the past TV should be hidden by default"
expect "$("$AX" text "Show past devices (1)" 5)" "found text" "the past-devices control should count the TV"
"$AX" capture-union "$OUT/583-1-cards-online-offline.png" devices_card_$SEEDED devices_card_$PRINTER devices_button_showPast

"$AX" press devices_button_showPast > /dev/null
expect "$("$AX" wait devices_card_$TV 5)" found "Show past devices should list the TV"
expect "$("$AX" textin devices_card_$TV "Offline" 5)" "found text" "the TV should read Offline"
expect "$("$AX" textin devices_card_$TV "Last seen 8 days ago" 5)" "found text" "the TV's last seen"
expect "$("$AX" text "Hide past devices" 5)" "found text" "the control should offer to hide them again"
"$AX" capture-union "$OUT/583-2-cards-past-shown.png" devices_card_$SEEDED devices_card_$PRINTER devices_card_$TV devices_button_showPast

quit

# MARK: Run 2: the same in the Pro mode table, whose status column says each state to VoiceOver

UITEST_SCAN_CLOCK=1 UITEST_SCAN_DROP_LAST=1 launch 2 Pro
# The table is wider than the default window; widen it so the status column shows.
"$AX" resize 1700 900 > /dev/null
expect "$("$AX" wait devices_row_pro$SEEDED 15)" found "run 2: the Pro table never showed"
for n in 1 2 3 4; do scan; done
expect "$("$AX" gone devices_row_pro$TV 3)" gone "Pro: the past TV should be hidden by default"
"$AX" press devices_button_showPast > /dev/null
expect "$("$AX" wait devices_row_pro$TV 5)" found "Pro: Show past devices should list the TV"
expect "$("$AX" textin devices_row_pro$SEEDED "Online, Last seen just now" 5)" "found text" "Pro: seeded Online"
expect "$("$AX" textin devices_row_pro$PRINTER "Offline, Last seen 30 min ago" 5)" "found text" "Pro: printer Offline"
expect "$("$AX" textin devices_row_pro$TV "Offline, Last seen 8 days ago" 5)" "found text" "Pro: TV Offline"
"$AX" capture-union "$OUT/583-3-pro-table.png" devices_row_pro$SEEDED devices_row_pro$PRINTER devices_row_pro$TV \
  devices_pro_presence_$SEEDED devices_pro_presence_$PRINTER devices_pro_presence_$TV

quit

# MARK: Run 3: a network not checked recently

UITEST_SCAN_CLOCK=1 UITEST_PRESENCE_OFFSET=3600 launch 3 Consumer
expect "$("$AX" wait devices_card_$SEEDED 15)" found "run 3: the seeded device's card never showed"
scan
expect "$("$AX" wait devices_card_$PRINTER 10)" found "run 3: the printer's card never showed"
for ip in $SEEDED $PRINTER; do
  expect "$("$AX" textin devices_card_$ip "Not checked recently" 5)" "found text" "run 3: $ip should be Not checked recently"
  expect "$("$AX" notextin devices_card_$ip "Online" 3)" "no text" "run 3: $ip must not read Online"
  expect "$("$AX" textin devices_card_$ip "Last seen 1 hour ago" 5)" "found text" "run 3: $ip last seen"
done
"$AX" capture-union "$OUT/583-4-cards-not-checked.png" devices_card_$SEEDED devices_card_$PRINTER
echo PASS
