#!/bin/zsh
# #491 S6 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1).
# Launches a Debug build with UI-test arguments and a stand-in model, presses Scan Network, and
# checks the dashboard's "since yesterday" brief:
#   answer:      the card (networkDetail_card_changeBrief) shows the key point, the model's paragraph
#                and the generated marker; the card alone is also captured;
#   unavailable: once the scan's events are recorded, no card.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/s6-change-brief.sh <Debug NetMonitor-macOS.app> <out-dir> answer|unavailable
set -euo pipefail
APP=$1
OUT=$2
MODE=$3
[[ $MODE == answer || $MODE == unavailable ]] || { echo "mode must be answer or unavailable"; exit 2; }
mkdir -p "$OUT"
SHOT=$OUT/s6-brief-$MODE.png
CARD_SHOT=$OUT/s6-brief-card.png
CARD=networkDetail_card_changeBrief
# Never validate a previous run's artifacts.
rm -f "$SHOT"
if [[ $MODE == answer ]]; then
  rm -f "$CARD_SHOT"
fi
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

# A sandboxed (signed) build keeps its temporary directory in its container.
entitlements=$(codesign -d --entitlements - --xml "$APP" 2>/dev/null || true)
if [[ $entitlements == *com.apple.security.app-sandbox* ]]; then
  bundle_id=$(/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' "$APP/Contents/Info.plist")
  TMP_ROOT=$HOME/Library/Containers/$bundle_id/Data/tmp
else
  TMP_ROOT=${TMPDIR:-$(getconf DARWIN_USER_TEMP_DIR)}
fi
EVENTS=${TMP_ROOT%/}/netmonitor-uitest-history/network-events.json

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files \
  --seed-test-device --seed-test-events --uitest-insight=$MODE > "$OUT/app-$MODE.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

[[ $("$AX" wait networkDetail_section_devices 30) == found* ]] || { echo "FAIL: dashboard never appeared"; exit 1; }
sleep 2
"$AX" menu "Scan Network"

# The store writes a second after a change: once the joined event is on disk, the scan has finished.
for _ in {1..30}; do
  grep -q 'Device Joined: uitest-printer' "$EVENTS" 2>/dev/null && break
  sleep 1
done
grep -q 'Device Joined: uitest-printer' "$EVENTS" || { echo "FAIL: the scan's events were never recorded"; exit 1; }

MARKER="Written by the on-device model from the events the app recorded"
if [[ $MODE == answer ]]; then
  result=$("$AX" wait $CARD 30)
  echo "$result"
  [[ $result == found* ]] || { echo "FAIL: $CARD is not on screen"; exit 1; }
  # The seeded connectivity event alone would show a card with no key point; wait for the scan's.
  for text in "1 device joined the network." "The app recorded changes on this network in the last day" "$MARKER"; do
    result=$("$AX" text "$text" 30)
    echo "$result"
    [[ $result == found* ]] || { echo "FAIL: \"$text\" is not on screen"; exit 1; }
  done
else
  # Give the brief time it would need to appear, then check it never did.
  sleep 5
  result=$("$AX" gone $CARD 1)
  echo "$result"
  [[ $result == gone* ]] || { echo "FAIL: $CARD is on screen"; exit 1; }
  for text in "SINCE YESTERDAY" "$MARKER"; do
    result=$("$AX" notext "$text" 1)
    echo "$result"
    [[ $result == no\ text* ]] || { echo "FAIL: \"$text\" is on screen"; exit 1; }
  done
fi
sleep 1
"$AX" capture "$SHOT"
if [[ $MODE == answer ]]; then
  "$AX" capture-element $CARD "$CARD_SHOT"
fi
echo "PASS ($MODE): $SHOT"
