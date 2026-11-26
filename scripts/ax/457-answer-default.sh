#!/bin/zsh
# #457 user flow (macOS AX procedure): on a fresh launch the Companion settings show
# "Answer model requests from iPhone" turned on, with nothing stored by the user.
# Launches a Debug build with --uitesting --in-memory-store, opens Settings > Companion, reads the
# toggle's value and captures the toggle only (no network details on screen).
# Run under the AX lock: lockf -t 3600 /tmp/nm-mini1-ax.lock scripts/ax/457-answer-default.sh <app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
rm -f "$OUT"/457-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

# The app has no isolated-defaults launch argument, so the check needs the key unset in the app's
# real preferences domain. Never lose the owner's saved choice: remember it, and put it back on every
# exit path (success, failure, signal).
DOMAIN=com.netmonitor.NetMonitor
KEY=netmonitor.companion.answersInsight
SAVED=$(defaults read $DOMAIN $KEY 2>/dev/null || true)
restore() {
    [[ -n ${PID:-} ]] && kill $PID 2>/dev/null || true
    [[ -n $SAVED ]] && defaults write $DOMAIN $KEY -bool "$([[ $SAVED == 1 ]] && echo YES || echo NO)"
    return 0
}
trap restore EXIT
if [[ -n $SAVED ]]; then echo "saved value $SAVED, restoring on exit"; fi
defaults delete $DOMAIN $KEY 2>/dev/null || true
"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files > "$OUT/app-457.log" 2>&1 &
PID=$!
export AX_PID=$PID

fail() { echo "FAIL: $1"; exit 1; }
expect() { echo "$1"; [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
"$AX" menu "Settings…" > /dev/null
expect "$("$AX" wait settings_tab_Companion 10)" found "Settings never showed the Companion tab"
"$AX" click settings_tab_Companion > /dev/null
expect "$("$AX" wait settings_toggle_answersInsight 10)" found "the answer toggle is missing"
expect "$("$AX" value settings_toggle_answersInsight)" 1 "the toggle is not on by default"
"$AX" capture-element settings_toggle_answersInsight "$OUT/457-answer-toggle-on.png"
echo "PASS"
