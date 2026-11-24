#!/bin/zsh
# #454 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1, #512).
# Launches a Debug build with UI-test arguments, the seeded device and --seed-security-devices (a
# camera with telnet 23 and HTTP 80 open, a NAS with SMB 445 open), and a stand-in model, then
# opens Tools > Security Readout:
#   answer:      the camera's high telnet finding is ranked first, the model's overview and the
#                generated marker show; clicking that row opens the camera's detail, whose
#                Security section lists its findings;
#   unavailable: the findings and their fixed text show, with no overview and no marker.
# Screenshots are the app window cropped to the readout or the detail sheet: only fixture devices.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/454-security-readout.sh <Debug NetMonitor-macOS.app> <out-dir> answer|unavailable
set -euo pipefail
APP=$1
OUT=$2
MODE=$3
[[ $MODE == answer || $MODE == unavailable ]] || { echo "mode must be answer or unavailable"; exit 2; }
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/454-$MODE-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-test-device \
  --seed-security-devices --uitest-insight=$MODE > "$OUT/app-$MODE.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

fail() { echo "FAIL: $1"; exit 1; }
expect() { echo "$1"; [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

TELNET="Telnet port 23 is open"
EXPLANATION="Telnet sends the password and the whole session unencrypted"
OVERVIEW="The app found open ports on this network that are worth closing"
MARKER="Written by the on-device model from the findings below"

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
"$AX" click sidebar_nav_tools > /dev/null
expect "$("$AX" wait tools_card_security_readout 10)" found "Tools never showed the Security Readout card"
"$AX" click tools_card_security_readout > /dev/null
expect "$("$AX" text "$TELNET" 15)" "found text" "the telnet finding is missing"
expect "$("$AX" text "$EXPLANATION" 3)" "found text" "the telnet finding's fixed explanation is missing"
expect "$("$AX" text "SMB file sharing port 445 is open" 3)" "found text" "the NAS's SMB finding is missing"
expect "$("$AX" text "HTTP admin page port 80 is open" 3)" "found text" "the camera's HTTP finding is missing"

# Ranked first: the first finding row in the window's element order is the camera's telnet one.
first_row=$("$AX" ids | grep -m1 '^securityReadout_row_' || true)
[[ $first_row == *-telnet-23 ]] || fail "the first row is not the telnet finding (got: $first_row)"
echo "first row: $first_row"

if [[ $MODE == answer ]]; then
  expect "$("$AX" text "$OVERVIEW" 20)" "found text" "the model's overview is missing"
  expect "$("$AX" text "$MARKER" 3)" "found text" "the generated marker is missing"
  "$AX" capture-in screen_securityReadout "$OUT/454-answer-readout.png"
  # The row opens the camera's detail, with its Security section.
  "$AX" press "$first_row" > /dev/null
  expect "$("$AX" wait deviceDetail_section_security 10)" found "the camera's Security section is missing"
  expect "$("$AX" text uitest-camera 5)" "found text" "the detail is not the camera's"
  "$AX" capture-in screen_deviceDetail "$OUT/454-answer-camera-detail.png"
  "$AX" capture-in deviceDetail_section_security "$OUT/454-answer-camera-security.png"
else
  # Give the overview the time it would need, then check it never came.
  sleep 3
  expect "$("$AX" notext "$OVERVIEW" 1)" "no text" "an overview shows without the model"
  expect "$("$AX" notext "$MARKER" 1)" "no text" "the generated marker shows without the model"
  "$AX" capture-in screen_securityReadout "$OUT/454-unavailable-readout.png"
fi
echo "PASS ($MODE)"
