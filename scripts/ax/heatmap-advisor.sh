#!/bin/zsh
# #455 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1).
# Launches a Debug build into the seeded weak-corner survey (--seed-heatmap-survey) with a stand-in
# model and checks the heatmap advisor in the Analyze sidebar:
#   answer:      the card shows the app's key points, the model's paragraph and the generated marker;
#   unavailable: the card shows the key points, with no model paragraph and no marker.
# The card alone is captured. Never touches an installed /Applications copy: it drives only the
# process it started.
# Usage: scripts/ax/heatmap-advisor.sh <Debug NetMonitor-macOS.app> <out-dir> answer|unavailable
set -euo pipefail
APP=$1
OUT=$2
MODE=$3
[[ $MODE == answer || $MODE == unavailable ]] || { echo "mode must be answer or unavailable"; exit 2; }
mkdir -p "$OUT"
SHOT=$OUT/heatmap-advisor-$MODE.png
# Never validate a previous run's artifacts.
rm -f "$SHOT"
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files \
  --seed-heatmap-survey --uitest-insight=$MODE > "$OUT/app-heatmap-$MODE.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

KEY_POINTS=("The north-east corner is weak (" "Try moving the access point toward the north-east corner.")
MODEL_TEXT="moving the access point toward it should help"
MARKER="Written by the on-device model from the survey's statistics"

result=$("$AX" text "SURVEY ADVICE" 40)
echo "$result"
[[ $result == found* ]] || { echo "FAIL: the advisor card never appeared"; exit 1; }
for text in "${KEY_POINTS[@]}"; do
  result=$("$AX" text "$text" 10)
  echo "$result"
  [[ $result == found* ]] || { echo "FAIL: key point \"$text\" is not on screen"; exit 1; }
done

if [[ $MODE == answer ]]; then
  for text in "$MODEL_TEXT" "$MARKER"; do
    result=$("$AX" text "$text" 20)
    echo "$result"
    [[ $result == found* ]] || { echo "FAIL: \"$text\" is not on screen"; exit 1; }
  done
else
  # Give an answer time it would need to appear, then check it never did.
  sleep 5
  for text in "$MODEL_TEXT" "$MARKER"; do
    result=$("$AX" notext "$text" 1)
    echo "$result"
    [[ $result == no\ text* ]] || { echo "FAIL: \"$text\" is on screen"; exit 1; }
  done
fi
sleep 1
"$AX" capture-in heatmap_card_advisor "$SHOT"
echo "PASS ($MODE): $SHOT"
