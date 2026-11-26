#!/bin/zsh
# #594 PR2 user flows (macOS AX procedure; XCUITest is blocked on mini-pro-1): devices grouped
# automatically, by a suggestion, and by hand, with Undo and "Not the same device".
#
#   1. Automatic: UITEST_SCAN_BONJOUR_PAIR=1 makes the fixture scan find 192.168.77.70 and .71
#      both answering for uitest-workstation.local. They show as one device whose Wi-Fi interface
#      reads "Grouped by Bonjour name". "Not the same device" on it splits them, with an undo toast,
#      and the next scan (same evidence) doesn't regroup them.
#   2. Suggestion: --seed-group-suggestion saves uitest-laptop (192.168.77.80) and
#      uitest-laptop-wifi (.81), both seen for uitest-laptop.local an hour ago. The laptop's detail
#      shows "Same Bonjour name as uitest-laptop-wifi: same device?"; "Same device" makes one
#      device, and the toast's Undo makes two again.
#   3. Manual: after a scan, "Same device as…" on uitest-device (192.168.77.77) picks
#      uitest-printer (.20): one device, named uitest-device. Edit › Undo makes two. Grouped again,
#      "Not the same device" on the printer's interface splits them, and a scan keeps them apart.
# macOS 27 stamps no identifier on the toast's container (deviceDetail_toast_undo), so the toast is
# found and cropped by its message, Undo and close button.
# Screenshots are the app window cropped to the elements: fixture devices only, no WAN or DNS.
# Never touches an installed /Applications copy: it drives only the process it started.
# On macOS 27 two Debug apps break AX for both: run under the AX lock, e.g.
#   lockf -t 3600 /tmp/nm-mini1-ax.lock scripts/ax/594-pr2-grouping.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/594pr2-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

fail() { echo "FAIL: $1"; kill ${PID:-0} 2>/dev/null || true; exit 1; }
expect() { [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

# launch <run> <arguments…>
launch() {
  local run=$1
  shift
  "$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-test-device \
    -netmonitor.devices.viewMode Consumer "$@" > "$OUT/app-$run.log" 2>&1 &
  PID=$!
  export AX_PID=$PID
  expect "$("$AX" wait networkDetail_section_devices 40)" found "run $run: the dashboard never appeared"
  "$AX" click sidebar_nav_devices > /dev/null
  "$AX" resize 1700 1000 > /dev/null
}

quit() {
  kill $PID 2>/dev/null || true
  wait $PID 2>/dev/null || true
  sleep 2
}

alive() { kill -0 $PID 2>/dev/null || fail "$1: the app quit or crashed"; }

scan() {
  "$AX" menu "Scan Network" > /dev/null
  sleep 3
}

# zsh runs no EXIT trap on errexit inside a function, so ZERR quits the app too.
trap 'kill ${PID:-0} 2>/dev/null || true' EXIT ZERR

# MARK: Run 1: automatic grouping, then Not the same device; the next scan keeps them apart

UITEST_SCAN_BONJOUR_PAIR=1 launch 1
scan
expect "$("$AX" wait devices_card_192.168.77.70 10)" found "run 1: the workstation should show at its lower address"
expect "$("$AX" gone devices_card_192.168.77.71 3)" gone "run 1: the second address must not be a second device"
"$AX" capture-union "$OUT/594pr2-1-one-device.png" devices_card_192.168.77.70
"$AX" click devices_card_192.168.77.70 > /dev/null
expect "$("$AX" wait deviceDetail_card_interfaces 10)" found "run 1: the detail should list both interfaces"
expect "$("$AX" textin deviceDetail_card_interfaces "Grouped by Bonjour name" 5)" "found text" "run 1: the label is missing"
expect "$("$AX" wait deviceDetail_label_groupedByBonjour_192.168.77.71 5)" found "run 1: the Wi-Fi row should carry the label"
"$AX" capture-union "$OUT/594pr2-2-label.png" deviceDetail_card_interfaces

"$AX" press deviceDetail_button_notSameDevice_192.168.77.71 > /dev/null
expect "$("$AX" wait deviceDetail_label_toastMessage 10)" found "run 1: no undo toast after Not the same device"
expect "$("$AX" text "192.168.77.71 is a separate device" 5)" "found text" "run 1: the toast's message"
"$AX" capture-union "$OUT/594pr2-3-toast-separate.png" deviceDetail_label_toastMessage deviceDetail_button_undo deviceDetail_button_dismissToast
expect "$("$AX" wait devices_card_192.168.77.71 10)" found "run 1: the separated interface should be a device of its own"
expect "$("$AX" gone deviceDetail_card_interfaces 5)" gone "run 1: one interface left, no Interfaces section"
scan
scan
expect "$("$AX" wait devices_card_192.168.77.71 5)" found "run 1: a scan regrouped the separated interface"
expect "$("$AX" wait devices_card_192.168.77.70 5)" found "run 1: the workstation is gone"
alive "run 1"
quit

# MARK: Run 2: the suggestion, Same device, and the toast's Undo

launch 2 --seed-group-suggestion
expect "$("$AX" wait devices_card_192.168.77.80 15)" found "run 2: the laptop's card never showed"
expect "$("$AX" wait devices_card_192.168.77.81 5)" found "run 2: the laptop's Wi-Fi card never showed"
"$AX" click devices_card_192.168.77.80 > /dev/null
# One banner per suggested device, its ID ending in that device's ID (as do its buttons').
BANNER=
for _ in {1..20}; do
  BANNER=$("$AX" ids | grep -m1 '^deviceDetail_banner_suggestion_' || true)
  [[ -n $BANNER ]] && break
  sleep 0.5
done
[[ -n $BANNER ]] || fail "run 2: no suggestion banner"
SUGGESTED=${BANNER#deviceDetail_banner_suggestion_}
expect "$("$AX" wait "deviceDetail_button_suggestionSameDevice_$SUGGESTED" 5)" found "run 2: the banner's Same device carries the device's ID"
expect "$("$AX" wait "deviceDetail_button_suggestionNotSameDevice_$SUGGESTED" 5)" found "run 2: the banner's Not the same device carries the device's ID"
expect "$("$AX" textin "$BANNER" "Same Bonjour name as uitest-laptop-wifi: same device?" 5)" "found text" \
  "run 2: the banner's question"
"$AX" capture-union "$OUT/594pr2-4-banner.png" "$BANNER"
"$AX" press "deviceDetail_button_suggestionSameDevice_$SUGGESTED" > /dev/null
expect "$("$AX" wait deviceDetail_label_toastMessage 10)" found "run 2: no undo toast after Same device"
expect "$("$AX" text "Grouped with uitest-laptop-wifi" 5)" "found text" "run 2: the toast's message"
"$AX" capture-union "$OUT/594pr2-5-toast-grouped.png" deviceDetail_label_toastMessage deviceDetail_button_undo deviceDetail_button_dismissToast
expect "$("$AX" gone devices_card_192.168.77.81 5)" gone "run 2: Same device should leave one device"
expect "$("$AX" wait deviceDetail_card_interfaces 10)" found "run 2: the device should list both interfaces"
expect "$("$AX" gone "$BANNER" 3)" gone "run 2: the banner should go once grouped"
"$AX" press deviceDetail_button_undo > /dev/null
expect "$("$AX" wait devices_card_192.168.77.81 10)" found "run 2: Undo should make two devices again"
expect "$("$AX" gone deviceDetail_card_interfaces 5)" gone "run 2: after Undo the laptop has one interface"
expect "$("$AX" gone deviceDetail_label_toastMessage 5)" gone "run 2: the toast should go after Undo"
alive "run 2"
quit

# MARK: Run 3: Same device as…, Edit › Undo, Not the same device, a scan

launch 3
scan
expect "$("$AX" wait devices_card_192.168.77.20 10)" found "run 3: the scan should find the printer"
"$AX" click devices_card_192.168.77.77 > /dev/null
groupWithPrinter() {
  expect "$("$AX" wait deviceDetail_button_sameDeviceAs 10)" found "run 3: no Same device as… button"
  "$AX" press deviceDetail_button_sameDeviceAs > /dev/null
  expect "$("$AX" wait sameDeviceAs_row_192_168_77_20 10)" found "run 3: the picker should list the printer"
  [[ ${1:-} == capture ]] && "$AX" capture-in screen_sameDeviceAs "$OUT/594pr2-6-picker.png" > /dev/null
  "$AX" press sameDeviceAs_row_192_168_77_20 > /dev/null
  expect "$("$AX" text "Grouped with uitest-printer" 10)" "found text" "run 3: the toast's message"
  expect "$("$AX" gone devices_card_192.168.77.77 5)" gone "run 3: the two should be one device"
  expect "$("$AX" textin devices_card_192.168.77.20 "uitest-device" 5)" "found text" "run 3: the device keeps uitest-device's name"
}
groupWithPrinter capture
"$AX" capture-union "$OUT/594pr2-7-manual-one-device.png" devices_card_192.168.77.20
# The undo manager names the action "Group Devices" (unit-tested), but this SwiftUI app's Edit menu
# reads plain "Undo" (as it does after typing in a text field): check the item, then its effect.
expect "$("$AX" menutitles Edit | head -1)" "Undo" "run 3: Edit › Undo is missing"
"$AX" menu "Undo" > /dev/null || fail "run 3: Edit › Undo is missing"
expect "$("$AX" wait devices_card_192.168.77.77 10)" found "run 3: Edit › Undo should make two devices again"
expect "$("$AX" gone deviceDetail_label_toastMessage 5)" gone "run 3: Edit › Undo should take the toast"

groupWithPrinter
expect "$("$AX" wait deviceDetail_button_notSameDevice_192.168.77.20 10)" found "run 3: no Not the same device on the printer"
"$AX" press deviceDetail_button_notSameDevice_192.168.77.20 > /dev/null
expect "$("$AX" wait devices_card_192.168.77.77 10)" found "run 3: Not the same device should split them"
scan
expect "$("$AX" wait devices_card_192.168.77.77 5)" found "run 3: a scan regrouped them"
expect "$("$AX" wait devices_card_192.168.77.20 5)" found "run 3: the printer is gone"
alive "run 3"
quit
echo PASS
