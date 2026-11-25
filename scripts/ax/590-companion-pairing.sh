#!/bin/zsh
# #590 user flow (macOS AX procedure; XCUITest is blocked on mini-pro-1, #512).
# Launches a Debug build with UI-test arguments and --seed-paired-phones (two made-up phones in an
# in-memory store; the Keychain is never touched), opens Settings > Companion and:
#   1. sees both paired phones listed;
#   2. removes "Test iPad" through Remove… and the confirmation, and sees only "Test iPhone" left;
#   3. opens Pair iPhone…, sees the one-time QR code and, behind "Can't scan?", the typed code;
#      then cancels, which closes the pairing window.
# Screenshots are the app window cropped to a paired-phone row or the pairing sheet: fixture data only.
# Never touches an installed /Applications copy: it drives only the process it started.
# Usage: scripts/ax/590-companion-pairing.sh <Debug NetMonitor-macOS.app> <out-dir>
set -euo pipefail
APP=$1
OUT=$2
mkdir -p "$OUT"
# Never validate a previous run's artifacts.
rm -f "$OUT"/590-*.png(N)
AX=$OUT/axdrive
swiftc -O "${0:A:h}/axdrive.swift" -o "$AX" 2>/dev/null

"$APP/Contents/MacOS/NetMonitor-macOS" --uitesting --in-memory-store --reset-history-files --seed-paired-phones \
  > "$OUT/app-590.log" 2>&1 &
PID=$!
trap 'kill $PID 2>/dev/null || true' EXIT
export AX_PID=$PID

fail() { echo "FAIL: $1"; exit 1; }
expect() { echo "$1"; [[ $1 == $2* ]] || fail "$3 (got: $1)"; }

expect "$("$AX" wait networkDetail_section_devices 40)" found "the dashboard never appeared"
"$AX" click sidebar_nav_settings > /dev/null
expect "$("$AX" wait settings_tab_Companion 10)" found "Settings never showed the Companion tab"
"$AX" click settings_tab_Companion > /dev/null

# 1. Both seeded phones are listed.
expect "$("$AX" wait "settings_row_pairedPhone_Test iPhone" 10)" found "Test iPhone is not listed"
expect "$("$AX" wait "settings_row_pairedPhone_Test iPad" 3)" found "Test iPad is not listed"
"$AX" capture-in "settings_row_pairedPhone_Test iPhone" "$OUT/590-mac-paired-iphone.png"
"$AX" capture-in "settings_row_pairedPhone_Test iPad" "$OUT/590-mac-paired-ipad.png"

# 2. Remove Test iPad.
"$AX" press "settings_button_removePhone_Test iPad" > /dev/null
expect "$("$AX" text "Remove Test iPad?" 5)" "found text" "the Remove confirmation never appeared"
"$AX" press settings_button_confirmRemovePhone > /dev/null || "$AX" pressin screen_companionSettings Remove > /dev/null
expect "$("$AX" gone "settings_row_pairedPhone_Test iPad" 5)" gone "Test iPad is still listed after Remove"
expect "$("$AX" wait "settings_row_pairedPhone_Test iPhone" 3)" found "Remove took the wrong phone"
"$AX" capture-in "settings_row_pairedPhone_Test iPhone" "$OUT/590-mac-after-remove-iphone-left.png"

# 3. Pair iPhone…: a QR code, and the typed code behind the disclosure.
"$AX" press settings_button_pairPhone > /dev/null
expect "$("$AX" wait pairing_image_qr 10)" found "the pairing QR code never appeared"
expect "$("$AX" text "The code works once and expires in ten minutes." 3)" "found text" "the one-time notice is missing"
"$AX" press pairing_toggle_showCode > /dev/null
expect "$("$AX" wait pairing_label_code 5)" found "the typed code never appeared"
"$AX" capture-in screen_pairingSheet "$OUT/590-mac-pairing-sheet.png"
"$AX" press pairing_button_cancel > /dev/null
expect "$("$AX" gone pairing_image_qr 5)" gone "Cancel didn't close the pairing sheet"
echo "PASS"
