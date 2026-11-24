#!/bin/zsh
# #451 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1, #512).
# Launches a Debug build with UI-test arguments and --uitest-troubleshoot=answer: stub checks on
# documentation addresses (10% loss to the router, a -80 dBm signal) and a stand-in model that
# reads "Zoom keeps freezing" as slow internet. Opens Tools > Troubleshoot, types the symptom and
# starts: the four steps show their raw results, "Weak signal" is ranked first above "Packet loss
# to your router", and the model's explanation and the generated marker show.
# Screenshots are the app window cropped to the troubleshooter: only fixture values.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/451-troubleshoot.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/451-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files \
  --uitest-troubleshoot=answer > "$OUT/app-451.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

fail() { echo "FAIL: $1"; exit 1; }
expect() { echo "$1"; [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
"$AX" click sidebar_nav_tools > /dev/null
expect "$("$AX" wait tools_card_troubleshoot 10)" found "Tools never showed the Troubleshoot card"
"$AX" click tools_card_troubleshoot > /dev/null
expect "$("$AX" wait troubleshoot_field_symptom 10)" found "the symptom field is missing"
"$AX" type troubleshoot_field_symptom "Zoom keeps freezing" > /dev/null
"$AX" press troubleshoot_button_start > /dev/null

# Each step's raw result.
expect "$("$AX" text "9 of 10 replies" 15)" "found text" "step 1 (router ping) has no result"
expect "$("$AX" text "apple.com resolved in 38 ms" 10)" "found text" "step 2 (DNS) has no result"
expect "$("$AX" text "Signal -80 dBm" 10)" "found text" "step 3 (Wi-Fi) has no result"
expect "$("$AX" text "Download 85 Mbps" 15)" "found text" "step 4 (speed test) has no result"

# Ranked: weak signal first.
expect "$("$AX" text "1. Weak signal" 10)" "found text" "weak signal is not ranked first"
expect "$("$AX" text "2. Packet loss to your router" 3)" "found text" "packet loss is not ranked second"

expect "$("$AX" text "Your Wi-Fi signal is weak" 20)" "found text" "the model's explanation is missing"
expect "$("$AX" text "Written by the on-device model from the likely causes above" 3)" "found text" "the generated marker is missing"
"$AX" capture-in screen_troubleshoot "$OUT/451-answer-troubleshoot.png"
echo "PASS"
