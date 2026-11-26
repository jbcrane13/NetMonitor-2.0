#!/bin/zsh
# #579 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1, #512).
# Launches a Debug build with UI-test arguments and --uitest-ask=answer: a scripted model over the
# seeded printer ("UITest Printer", offline, 192.0.2.57), and the fixture's live tools, which ping
# a fake on the documentation network 192.0.2.0/24 (nothing real is pinged). Opens Tools > Ask and
# asks "Is the printer answering right now?": the model's "Yes, … is answering" is dropped, its
# other sentence shows, and the app's measurement line shows with its time. The printer's saved
# status beside the citation stays "Not checked recently". Then "How is my connection?": the
# app's line gives the connection type and the gateway and internet pings.
# Screenshots are the app window cropped to the Ask sheet: only fixture values.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: lockf -t 3600 /tmp/nm-mini1-ax.lock scripts/ax/579-ask-live.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/579-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files \
  --uitest-ask=answer > "$OUT/app-579.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

fail() { echo "FAIL: $1"; exit 1; }
expect() { echo "$1"; [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
# The sidebar may start collapsed (the window's saved state): open it with the toolbar's toggle.
if [[ "$("$AX" wait sidebar_nav_tools 3)" != found* ]]; then
  "$AX" resize 1400 900 > /dev/null
  "$AX" clickat main-AppWindow-1 113 26 > /dev/null
  expect "$("$AX" wait sidebar_nav_tools 5)" found "the sidebar never opened"
fi
"$AX" click sidebar_nav_tools > /dev/null
expect "$("$AX" wait tools_card_ask 10)" found "Tools never showed the Ask card"
"$AX" click tools_card_ask > /dev/null
expect "$("$AX" wait ask_field_question 10)" found "the question field is missing"

"$AX" type ask_field_question "Is the printer answering right now?" > /dev/null
"$AX" press ask_button_ask > /dev/null
expect "$("$AX" text "It is a printer at 192.0.2.57." 15)" "found text" "the answer is missing"
# The model's presence sentence is the app's to state: it is dropped.
expect "$("$AX" notext "is answering right now" 2)" "no text" "the model's presence sentence was shown"
expect "$("$AX" wait ask_label_measurement_1 5)" found "the app's measurement line is missing"
expect "$("$AX" text "UITest Printer: 3 of 3 replies, 4 ms average, measured at" 3)" "found text" "the measurement has the wrong text"
expect "$("$AX" text "Written by the on-device model from the records below" 3)" "found text" "the generated marker is missing"
expect "$("$AX" wait ask_citation_device_1 5)" found "the printer is not cited"
# A live reply is never saved as presence: the citation keeps the scan's status.
expect "$("$AX" text "Not checked recently" 3)" "found text" "the citation's saved status changed"
"$AX" capture-in screen_ask "$OUT/579-ask-ping.png"

"$AX" type ask_field_question "How is my connection?" > /dev/null
"$AX" press ask_button_ask > /dev/null
expect "$("$AX" text "The connection is Wi-Fi. The gateway is at 192.0.2.1." 15)" "found text" "the connection answer is missing"
expect "$("$AX" text "Wi-Fi · gateway: 3 of 3 replies, 2 ms average · internet: 3 of 3 replies, 15 ms average, measured at" 5)" \
  "found text" "the connection measurement is missing"
"$AX" capture-in screen_ask "$OUT/579-ask-connection.png"
echo "PASS"
