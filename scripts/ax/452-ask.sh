#!/bin/zsh
# #452 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1, #512).
# Launches a Debug build with UI-test arguments and --uitest-ask=answer: a scripted model that
# calls the app's real tools on a seeded printer ("UITest Printer", offline, 192.0.2.57) and two
# joins this week. Opens Tools > Ask, asks "Is the printer up?": the answer, the generated marker
# and the printer's citation show. Clicking the citation opens the printer's device detail.
# Screenshots are the app window cropped to the Ask sheet and the detail: only fixture values.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/452-ask.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/452-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files \
  --uitest-ask=answer > "$OUT/app-452.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

fail() { echo "FAIL: $1"; exit 1; }
expect() { echo "$1"; [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
"$AX" click sidebar_nav_tools > /dev/null
expect "$("$AX" wait tools_card_ask 10)" found "Tools never showed the Ask card"
"$AX" click tools_card_ask > /dev/null
expect "$("$AX" wait ask_field_question 10)" found "the question field is missing"
"$AX" type ask_field_question "Is the printer up?" > /dev/null
"$AX" press ask_button_ask > /dev/null

expect "$("$AX" text "UITest Printer is offline." 15)" "found text" "the answer is missing"
expect "$("$AX" text "Written by the on-device model from the records below" 3)" "found text" "the generated marker is missing"
expect "$("$AX" wait ask_citation_device_1 5)" found "the printer is not cited"
"$AX" capture-in screen_ask "$OUT/452-ask-printer.png"

"$AX" press ask_citation_device_1 > /dev/null
expect "$("$AX" wait screen_deviceDetail 10)" found "the cited printer's detail never opened"
expect "$("$AX" text "UITest Printer" 5)" "found text" "detail does not show the printer"
"$AX" capture-in screen_deviceDetail "$OUT/452-ask-printer-detail.png"
echo "PASS"
