#!/bin/zsh
# #594 PR1 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1): one device on two
# interfaces reads as one device.
#
# --seed-device-group writes, through DeviceGroupWriter, "UITest Studio Mac": its Ethernet
# interface (192.168.77.60, the primary, with the name and notes) offline since two hours ago, and
# its Wi-Fi interface (192.168.77.61) with notes of its own. The fixture scan finds only the Wi-Fi
# interface. Then:
#   1. the Devices list shows one card for the device, at the Wi-Fi address, reading Online;
#   2. its detail lists both interfaces under Interfaces, shows both interfaces' notes and the
#      primary's serial (#561);
#   3. Remove this interface on the Wi-Fi interface (confirmed, as it has notes) leaves one device,
#      at the Ethernet address, still named.
# Run 2 removes the Ethernet interface (the primary, the row the detail shows) instead; run 3 does
# that from the Pro detail sheet. Both leave one device at the Wi-Fi address, and the app
# keeps running. Run 4 seeds a third interface, starts editing the device, removes the primary and
# presses Done: the removed primary's name draft must not be saved onto the new primary.
# Screenshots are the app window cropped to the elements: fixture devices only, no WAN or DNS.
# Never touches an installed /Applications copy: it drives only the process it started.
# On macOS 27 two Debug apps break AX for both: run under the AX lock, e.g.
#   lockf -t 3600 /tmp/nm-mini1-ax.lock scripts/ax/594-device-group.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/594-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

fail() { echo "FAIL: $1"; exit 1; }
expect() { [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

ETHERNET=192.168.77.60
WIFI=192.168.77.61
NAME="UITest Studio Mac"

# launch <run> <Consumer|Pro>: the view mode comes from the argument domain, never saved.
launch() {
  "$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files \
    --seed-device-group -netmonitor.devices.viewMode "$2" > "$OUT/app-$1.log" 2>&1 &
  PID=$!
  export AX_PID=$PID
  expect "$("$AX" wait networkDetail_section_devices 40)" found "run $1: the dashboard never appeared"
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
  "$AX" menu "Scan Network"
  sleep 3
}

confirmRemoval() {
  expect "$("$AX" text "Remove $1 from this device?" 5)" "found text" "removing $1 (it has notes) should ask first"
  "$AX" press deviceDetail_button_confirmRemoveInterface > /dev/null 2>&1 || fail "the confirmation's Remove Interface button"
}

trap 'kill $PID 2>/dev/null || true' EXIT

# MARK: Run 1: one device, online through its Wi-Fi interface; detail; remove the Wi-Fi interface

launch 1 Consumer
# Before any scan both interfaces were last seen together; the lower address is the current one.
expect "$("$AX" wait devices_card_$ETHERNET 15)" found "the seeded device's card never showed"
expect "$("$AX" gone devices_card_$WIFI 3)" gone "the group showed a second card before the scan"

scan
expect "$("$AX" wait devices_card_$WIFI 10)" found "after the scan the device should show at its Wi-Fi address"
expect "$("$AX" gone devices_card_$ETHERNET 3)" gone "the Ethernet interface must not show as a second device"
expect "$("$AX" textin devices_card_$WIFI "$NAME" 5)" "found text" "the card should carry the primary's name"
expect "$("$AX" textin devices_card_$WIFI "Online" 5)" "found text" "the device should read Online when only its Wi-Fi answered"
expect "$("$AX" notextin devices_card_$WIFI "Offline" 3)" "no text" "the device must not read Offline"
"$AX" capture-union "$OUT/594-1-list-one-device.png" devices_card_$WIFI

"$AX" click devices_card_$WIFI > /dev/null
expect "$("$AX" wait deviceDetail_card_interfaces 10)" found "the detail should list the interfaces"
expect "$("$AX" textin deviceDetail_card_interfaces $ETHERNET 5)" "found text" "Interfaces should list the Ethernet address"
expect "$("$AX" textin deviceDetail_card_interfaces $WIFI 5)" "found text" "Interfaces should list the Wi-Fi address"
expect "$("$AX" text "Ethernet port behind the desk" 5)" "found text" "the primary's notes should show"
expect "$("$AX" text "Wi-Fi when undocked" 5)" "found text" "the Wi-Fi interface's notes should show"
"$AX" capture-union "$OUT/594-2-detail-interfaces.png" deviceDetail_card_interfaces
expect "$("$AX" textin deviceDetail_label_serial "C02UITEST0001" 5)" "found text" "the detail should show the primary's serial"
"$AX" capture-union "$OUT/594-5-detail-serial.png" deviceDetail_card_hardware
"$AX" scroll deviceDetail_card_interfaces -300 > /dev/null
"$AX" capture-union "$OUT/594-3-detail-notes.png" deviceDetail_card_notes

"$AX" press deviceDetail_button_removeInterface_$WIFI > /dev/null
confirmRemoval $WIFI
expect "$("$AX" gone deviceDetail_card_interfaces 10)" gone "a device of one interface has no Interfaces section"
expect "$("$AX" wait devices_card_$ETHERNET 10)" found "the remaining interface should be the device"
expect "$("$AX" gone devices_card_$WIFI 3)" gone "the removed interface must be gone"
expect "$("$AX" textin devices_card_$ETHERNET "$NAME" 5)" "found text" "the remaining device keeps its name"
expect "$("$AX" notext "Wi-Fi when undocked" 3)" "no text" "the removed interface's notes went with it"
alive "run 1"
"$AX" capture-union "$OUT/594-4-after-remove.png" devices_card_$ETHERNET
quit

# MARK: Run 2: remove the primary, the row the detail shows

launch 2 Consumer
scan
"$AX" click devices_card_$WIFI > /dev/null
expect "$("$AX" wait deviceDetail_card_interfaces 10)" found "run 2: the detail should list the interfaces"
"$AX" press deviceDetail_button_removeInterface_$ETHERNET > /dev/null
confirmRemoval $ETHERNET
expect "$("$AX" gone deviceDetail_card_interfaces 10)" gone "run 2: one interface left, no Interfaces section"
expect "$("$AX" wait devices_card_$WIFI 10)" found "run 2: the Wi-Fi interface should remain as the device"
expect "$("$AX" gone devices_card_$ETHERNET 3)" gone "run 2: the removed primary must be gone"
expect "$("$AX" text "Wi-Fi when undocked" 5)" "found text" "run 2: the detail stays on the remaining interface"
alive "run 2"
quit

# MARK: Run 3: the same from the Pro detail sheet (opened from the dashboard's device panel;
# the Pro table is wider than the screen, so its rows' centres are off-window)

launch 3 Consumer
"$AX" menu "Scan Network"
sleep 3
"$AX" click "$("$AX" ids | tr ' ' '\n' | grep -m1 '^sidebar_row_network')" > /dev/null
expect "$("$AX" wait networkDevicesPanel_row_$WIFI 15)" found "run 3: the panel should show the device at its Wi-Fi address"
expect "$("$AX" gone networkDevicesPanel_row_$ETHERNET 3)" gone "run 3: one panel row for the device"
"$AX" clickat networkDevicesPanel_row_$WIFI 60 12 > /dev/null
expect "$("$AX" wait deviceDetail_card_interfaces 10)" found "run 3: the sheet should list the interfaces"
"$AX" press deviceDetail_button_removeInterface_$ETHERNET > /dev/null
confirmRemoval $ETHERNET
expect "$("$AX" gone screen_deviceDetail 10)" gone "run 3: removing the shown row closes the sheet"
sleep 1
expect "$("$AX" wait networkDevicesPanel_row_$WIFI 10)" found "run 3: the Wi-Fi interface should remain"
expect "$("$AX" gone networkDevicesPanel_row_$ETHERNET 3)" gone "run 3: the removed primary must be gone"
alive "run 3"
quit
# MARK: Run 4: a draft never moves to the new primary

UITEST_GROUP_THIRD=1 launch 4 Consumer
scan
expect "$("$AX" wait devices_card_$WIFI 10)" found "run 4: the device should show at its Wi-Fi address"
"$AX" click devices_card_$WIFI > /dev/null
expect "$("$AX" wait deviceDetail_card_interfaces 10)" found "run 4: the detail should list the interfaces"
"$AX" press deviceDetail_button_edit > /dev/null
"$AX" press deviceDetail_button_removeInterface_$ETHERNET > /dev/null
confirmRemoval $ETHERNET
expect "$("$AX" wait deviceDetail_card_interfaces 10)" found "run 4: two interfaces remain, still a group"
"$AX" press deviceDetail_button_edit > /dev/null
sleep 1
expect "$("$AX" notextin devices_card_$WIFI "$NAME" 3)" "no text" "run 4: the removed primary's name was saved onto the new primary"
alive "run 4"
quit
echo PASS
