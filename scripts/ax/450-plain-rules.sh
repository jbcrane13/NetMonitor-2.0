#!/bin/zsh
# #450 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1, #512).
# Launches a Debug build with UI-test arguments, the seeded device, --seed-security-devices (whose
# NAS is the storage-type "uitest-nas") and --uitest-insight=answer, which reads rules from the
# real model's recorded answers. Alert rules go to the UI-test suite, never the user's rules.
#   1. Settings > Rules: types "Tell me if the NAS is down for more than five minutes", sees the
#      draft on the NAS with its five-minute duration and the generated marker, confirms, and sees
#      the rule in the list on uitest-nas. Monitoring is stopped, so the draft offers to start it;
#      Confirm with it on starts monitoring (the same sentence then drafts with no offer).
#   2. Renames the NAS in its device detail and sees the rule still listed on it, by the new name.
#   3. Types "what's the weather" and sees the unsupported message; no rule is drafted.
# Screenshots are the app window cropped to the draft, the rule's row or the message: only fixture devices, never the sidebar's network name.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/450-plain-rules.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/450-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-test-device \
  --seed-security-devices --uitest-insight=answer > "$OUT/app-450.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

fail() { echo "FAIL: $1"; exit 1; }
expect() { echo "$1"; [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

NAS_RULE="Goes offline · for 5 minutes · device"
NOTE="Fires once uitest-nas has been unreachable for 5 minutes"
START="Start monitoring when I confirm"
UNSUPPORTED="I can create alerts for a device going offline, coming online, new devices, or high latency"

open_rules() {
  "$AX" click sidebar_nav_settings > /dev/null
  expect "$("$AX" wait settings_tab_Rules 10)" found "Settings never showed the Rules tab"
  "$AX" click settings_tab_Rules > /dev/null
  expect "$("$AX" wait rules_field_describe 10)" found "the Describe a rule field is missing"
}

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
open_rules
expect "$("$AX" text "No rules yet" 5)" "found text" "the UI-test rules were not empty"

# 1. Describe, review, confirm.
"$AX" type rules_field_describe "Tell me if the NAS is down for more than five minutes" > /dev/null
"$AX" press rules_button_parse > /dev/null
expect "$("$AX" wait rules_draft_card 15)" found "no draft appeared"
expect "$("$AX" text "Drafted by the on-device model from your words" 3)" "found text" "the generated marker is missing"
expect "$("$AX" text "uitest-nas (192.168.77.40)" 3)" "found text" "the draft is not on the NAS"
expect "$("$AX" text "For at least 5 minutes" 3)" "found text" "the draft lost the five-minute duration"
expect "$("$AX" text "$NOTE" 3)" "found text" "the duration note is missing"
expect "$("$AX" text "No rules yet" 1)" "found text" "a rule was saved before Confirm"
expect "$("$AX" text "$START" 3)" "found text" "monitoring is stopped but Start monitoring isn't offered"
"$AX" capture-in rules_draft_card "$OUT/450-draft.png"
"$AX" press rules_button_confirm > /dev/null
expect "$("$AX" text "$NAS_RULE uitest-nas" 10)" "found text" "the confirmed rule is not listed on uitest-nas"
expect "$("$AX" notext "No rules yet" 2)" "no text" "the empty-list label still shows"

# Confirm started monitoring: the same sentence now drafts on the NAS's target, with no offer to start it.
"$AX" type rules_field_describe "Tell me if the NAS is down for more than five minutes" > /dev/null
"$AX" press rules_button_parse > /dev/null
expect "$("$AX" wait rules_draft_card 15)" found "no second draft appeared"
expect "$("$AX" notext "$START" 2)" "no text" "Start monitoring is still offered, so Confirm didn't start it"
expect "$("$AX" notext "Also add a monitoring target" 1)" "no text" "the NAS's new target wasn't saved"
"$AX" capture-in rules_draft_card "$OUT/450-draft-monitoring.png"
"$AX" press rules_draft_cancel > /dev/null
ROW=$("$AX" ids | grep -m1 '^rules_row_' || true)
[[ -n $ROW ]] || fail "the rule row is missing"
"$AX" capture-in "$ROW" "$OUT/450-rule-listed.png"

# 2. Rename the NAS; the rule follows it.
"$AX" click sidebar_nav_devices > /dev/null
expect "$("$AX" wait devices_card_192.168.77.40 15)" found "the NAS card is missing"
"$AX" click devices_card_192.168.77.40 > /dev/null
expect "$("$AX" wait deviceDetail_button_edit 10)" found "the NAS detail never opened"
"$AX" press deviceDetail_button_edit
expect "$("$AX" text "Done" 5)" "found text" "the detail never entered editing"
# The header card's identifier is stamped over its name field (macOS 27), so type into its text field.
"$AX" typefield deviceDetail_card_header "Basement NAS"
"$AX" press deviceDetail_button_edit
expect "$("$AX" text "Basement NAS" 5)" "found text" "the rename did not show"
open_rules
expect "$("$AX" text "$NAS_RULE Basement NAS" 10)" "found text" "the rule no longer shows the renamed NAS"
"$AX" capture-in "$ROW" "$OUT/450-rule-after-rename.png"

# 3. Nonsense gives the message, not a rule.
"$AX" type rules_field_describe "what's the weather" > /dev/null
"$AX" press rules_button_parse > /dev/null
expect "$("$AX" wait rules_draft_message 15)" found "no message for unsupported input"
expect "$("$AX" text "$UNSUPPORTED" 3)" "found text" "the unsupported message is wrong"
expect "$("$AX" notext "Drafted by the on-device model" 1)" "no text" "a draft appeared for nonsense"
"$AX" capture-in rules_draft_message "$OUT/450-unsupported.png"
echo "PASS"
