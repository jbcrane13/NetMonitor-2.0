#!/bin/zsh
# #491 S3 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1, #512).
# Launches a Debug build with UI-test arguments and seeded events (today and ten days ago), opens
# Tools > Timeline, picks "Today" (the old event goes, today's stays) and "All" (both show), then
# scans with File > Scan Network, reopens the Timeline and checks "Scan Complete" and
# "Device Joined: uitest-printer". Last, Clear All must ask first, and Cancel keeps the log.
# Screenshots are the app window cropped to the Timeline (the confirmation one is the window), so
# no other window and none of the dashboard's WAN or DNS data appear.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/s3-timeline.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/s3-timeline-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-test-device \
  --seed-test-events > "$OUT/app.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

fail() { echo "FAIL: $1"; exit 1; }
expect() { [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

open_timeline() {
  "$AX" click sidebar_nav_tools > /dev/null
  expect "$("$AX" wait tools_card_timeline 10)" found "Tools never showed the Timeline card"
  "$AX" click tools_card_timeline > /dev/null
  expect "$("$AX" wait timeline_picker_range 10)" found "the Timeline never opened"
}

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
open_timeline

# All is the default: both seeded events show.
expect "$("$AX" text "UITest Event Today" 10)" "found text" "All: today's event is missing"
expect "$("$AX" text "UITest Event 10 Days Ago" 5)" "found text" "All: the ten-days-ago event is missing"

"$AX" pressin timeline_picker_range Today
# Checked with today's event still present, so an absence can't pass on an empty or closed screen.
expect "$("$AX" notext "UITest Event 10 Days Ago" 5)" "no text" "Today: the ten-days-ago event still shows"
expect "$("$AX" text "UITest Event Today" 3)" "found text" "Today: today's event is missing"
"$AX" capture-in screen_networkTimeline "$OUT/s3-timeline-today.png"

"$AX" pressin timeline_picker_range All
expect "$("$AX" text "UITest Event 10 Days Ago" 5)" "found text" "All again: the ten-days-ago event is missing"
expect "$("$AX" text "UITest Event Today" 3)" "found text" "All again: today's event is missing"
"$AX" capture-in screen_networkTimeline "$OUT/s3-timeline-all.png"

# The Timeline loads when it opens, so scan, wait for the events, then reopen it.
"$AX" menu "Scan Network"
sleep 3
open_timeline
expect "$("$AX" text "Device Joined: uitest-printer" 20)" "found text" "the scan's join is missing"
expect "$("$AX" text "Scan Complete" 5)" "found text" "Scan Complete is missing"
"$AX" capture-in screen_networkTimeline "$OUT/s3-timeline-after-scan.png"

# Clear All deletes the whole log, so it asks first; Cancel keeps everything.
"$AX" pressin timeline_picker_range Today
"$AX" press timeline_button_clearAll
expect "$("$AX" text "Delete all network events?" 5)" "found text" "Clear All didn't ask first"
"$AX" capture "$OUT/s3-timeline-clear-confirm.png"
"$AX" press timeline_button_cancelClearAll
expect "$("$AX" notext "Delete all network events?" 5)" "no text" "Cancel didn't close the confirmation"
"$AX" pressin timeline_picker_range All
expect "$("$AX" text "UITest Event 10 Days Ago" 5)" "found text" "Cancel lost the event outside the range"
expect "$("$AX" text "Device Joined: uitest-printer" 3)" "found text" "Cancel lost the scan's join"
echo PASS
