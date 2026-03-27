#!/bin/bash
# Mac Screenshot Capture Script
# Navigate to each screen when prompted, then press ENTER to capture.

DIR="$(dirname "$0")/mac"
mkdir -p "$DIR"

# Get the NetMonitor window ID
WID=$(swift -e '
import CoreGraphics
let list = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as! [[String: Any]]
for w in list {
    let owner = w["kCGWindowOwnerName"] as? String ?? ""
    let layer = w["kCGWindowLayer"] as? Int ?? -1
    let wid = w["kCGWindowNumber"] as? Int ?? 0
    let name = w["kCGWindowName"] as? String ?? ""
    if owner.contains("NetMonitor") && layer == 0 && !name.isEmpty {
        print(wid)
        break
    }
}
')

if [ -z "$WID" ]; then
    echo "ERROR: NetMonitor-macOS window not found. Launch the app first."
    exit 1
fi
echo "Found NetMonitor window ID: $WID"
echo ""

SCREENS=(
    "01-dashboard.png|Dashboard (main network view with all cards)"
    "02-devices-consumer.png|Devices list - Consumer mode (card grid)"
    "03-devices-pro.png|Devices list - Pro mode (table view)"
    "04-device-detail.png|Device detail (click any device to open detail sheet)"
    "05-tools.png|Tools grid (click Tools in sidebar)"
    "06-ping.png|Ping tool (run a ping so the chart shows)"
    "07-traceroute.png|Traceroute tool (run a trace)"
    "08-settings.png|Settings (click Settings in sidebar)"
    "09-speed-test.png|Speed Test tool (or any other tool you want to show)"
    "10-network-map.png|Any other screen you want to capture"
)

echo "=== NetMonitor macOS Screenshot Capture ==="
echo "Navigate to each screen, then press ENTER to capture."
echo ""

for entry in "${SCREENS[@]}"; do
    IFS='|' read -r filename description <<< "$entry"
    echo "📸 Next: $description"
    echo "   Navigate to this screen, then press ENTER..."
    read -r
    screencapture -x -l "$WID" "$DIR/$filename"
    echo "   ✓ Saved: $filename"
    echo ""
done

echo "=== Done! Screenshots saved to: $DIR ==="
ls -la "$DIR"
