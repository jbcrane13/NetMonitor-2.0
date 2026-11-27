#!/bin/zsh
# #628 PR B user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1).
# Launches a Debug build with UI-test arguments and UITEST_IDENTITY=ask: the fixture's local network
# ("Home office", 192.168.77.0/24) was identified by one router, and the Mac now sees another on the
# same subnet. The Devices screen must ask "Which network is this?", show the seeded device as
# history ("Not checked: which network is this?"), and save nothing from a scan. Answering "Same as
# Home office" settles it: one scan runs and saves the fixture's printer, shown Online.
# Everything is fixture data in a throwaway store and defaults suite: no real network, no saved
# preferences. Never touches an installed /Applications copy: it drives only the process it started.
# The question is reached from the dashboard's device panel banner, as a user finds it.
# Usage: scripts/ax/628-mac-identity.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
rm -f "$OUT"/628b-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

UITEST_IDENTITY=ask \
  "$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-test-device \
  > "$OUT/app.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID
START=$(date '+%Y-%m-%d %H:%M:%S')

fail() { echo "FAIL: $1"; exit 1; }
expect() { [[ $1 == $2* ]] || fail "$3 (got: $1)"; }
# The sidebar may start collapsed in a narrow window, and collapses again after a sheet: widen the
# window and open it.
open_sidebar() {
  if [[ "$("$AX" wait sidebar_nav_devices 3)" != found* ]]; then
    "$AX" resize 1400 900 > /dev/null
    "$AX" clickat main-AppWindow-1 113 26 > /dev/null
    expect "$("$AX" wait sidebar_nav_devices 5)" found "the sidebar never opened"
  fi
}

TITLE=devices_identity_title
NEW=devices_identity_new
SEED=devices_card_192.168.77.77
PRINTER=devices_card_192.168.77.20

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
open_sidebar
# 0. The dashboard's device panel points at the question (#645): its Answer opens the Devices view.
expect "$("$AX" wait dashboard_identity_button_answer 15)" found "the dashboard doesn't point at the question"
"$AX" capture-union "$OUT/628b-0-dashboard-banner.png" dashboard_identity_text dashboard_identity_button_answer
"$AX" press dashboard_identity_button_answer > /dev/null
expect "$("$AX" wait devices_identity_title 10)" found "the banner's Answer didn't open the question"
# The Devices sheet sits over the dashboard: close it, and take the card through the sidebar, so no
# capture can include the dashboard behind it.
"$AX" press devices_button_close > /dev/null
expect "$("$AX" gone devices_identity_title 10)" gone "the Devices sheet didn't close"
open_sidebar
"$AX" click sidebar_nav_devices > /dev/null

# 1. The question, and the saved device as history.
# macOS 27 doesn't expose the card's own identifier: its title and buttons carry theirs.
expect "$("$AX" wait $TITLE 15)" found "the question never showed"
expect "$("$AX" value $TITLE)" "Which network is this?" "the card doesn't ask which network this is"
expect "$("$AX" wait $SEED 10)" found "the seeded device's card never showed"
expect "$("$AX" textin $SEED "Not checked: which network is this?" 5)" "found text" "the saved device isn't shown as history"
"$AX" capture-union "$OUT/628b-1-question-history.png" $TITLE devices_identity_detail $NEW $SEED

# 2. A scan while it's open saves nothing.
"$AX" menu "Scan Network"
expect "$("$AX" wait $PRINTER 3)" TIMEOUT "a scan saved the printer while the question was open"
expect "$("$AX" textin $SEED "Not checked: which network is this?" 2)" "found text" "the saved device stopped reading as history"

# 3. The answer: same network. One scan runs and saves the printer.
"$AX" ids > "$OUT/ids.txt"
SAME=$(grep -m1 '^devices_identity_same_' "$OUT/ids.txt") || fail "no Same as option"
expect "$("$AX" press "$SAME")" pressed "couldn't answer the question"
expect "$("$AX" gone $TITLE 10)" gone "the question stayed after the answer"
expect "$("$AX" wait $PRINTER 15)" found "no scan saved the printer after the answer"
expect "$("$AX" textin $PRINTER Online 5)" "found text" "the printer's card doesn't say Online"
expect "$("$AX" notextin $SEED "Not checked: which network is this?" 5)" "no text" "the saved device still reads as history"
"$AX" capture-union "$OUT/628b-2-answered.png" $SEED $PRINTER

LOGS=$(/usr/bin/log show --start "$START" --predicate "processIdentifier == $PID AND category == 'discovery'" --style compact 2>/dev/null)
HELD=$(print -r -- "$LOGS" | grep -c "which network this is isn't settled" || true)
SETTLED=$(print -r -- "$LOGS" | grep -c "Scan started (identified)" || true)
[[ $HELD -ge 1 ]] || fail "expected the held scan in the app's log (got $HELD)"
[[ $SETTLED -eq 1 ]] || fail "expected one scan once identified (got $SETTLED)"
echo "log: $HELD held scan(s), $SETTLED scan once identified"

# 4. A network known only from before identification, whose devices the probe can't clearly match:
# "Is this Home office?", its saved device shown as history meanwhile. One Debug app at a time.
kill $PID 2>/dev/null || true
wait $PID 2>/dev/null || true
UITEST_IDENTITY=legacy \
  "$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-test-device \
  > "$OUT/app-legacy.log" 2>&1 &
PID=$!
export AX_PID=$PID
expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared (legacy)"
if [[ "$("$AX" wait sidebar_nav_devices 3)" != found* ]]; then
  "$AX" resize 1400 900 > /dev/null
  "$AX" clickat main-AppWindow-1 113 26 > /dev/null
fi
"$AX" click sidebar_nav_devices > /dev/null
expect "$("$AX" wait $TITLE 20)" found "the legacy question never showed"
expect "$("$AX" value $TITLE)" "Is this Home office?" "the card doesn't ask whether this is Home office"
expect "$("$AX" textin $SEED "Not checked: which network is this?" 5)" "found text" "the legacy network's device isn't history"
"$AX" capture-union "$OUT/628b-3-legacy-question.png" $TITLE devices_identity_detail $NEW $SEED
echo PASS
