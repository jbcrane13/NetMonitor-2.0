# Pro Mode Table Redesign

## Problem
Pro mode device table has cramped rows, misaligned columns, empty data columns, and no device type inference.

## Solution

### Visual Fixes (ProModeRowView + proModeHeaderRow)
- Row vertical padding: 6pt -> 12pt
- Font size: `.caption` -> `.callout`/`.body` for primary data
- Consistent fixed-width column system:

| Column    | Width       | Align   | Content                              |
|-----------|-------------|---------|--------------------------------------|
| Status    | 36pt fixed  | center  | Colored dot                          |
| IP        | 130pt fixed | leading | Monospaced                           |
| Name      | flex min150 | leading | displayName, bold if custom          |
| Type      | 32pt fixed  | center  | DeviceType SF Symbol icon            |
| Vendor    | 120pt fixed | leading | From MAC vendor lookup               |
| MAC       | 110pt fixed | leading | Last 8 chars, monospaced             |
| Ports     | 90pt fixed  | leading | Comma-joined, info-colored if present|
| Latency   | 70pt fixed  | trailing| Color-coded via latencyColor()       |
| Last Seen | 70pt fixed  | trailing| Relative time                        |

- No alternating row backgrounds (may revisit later)
- Header gets bottom border, semibold weight

### Device Type Inference (DeviceTypeInferenceService)
New service in NetMonitorCore. Runs post-scan, updates `LocalDevice.deviceType` from `.unknown`.

Priority chain (first match wins):
1. `isGateway` flag -> `.router`
2. Hostname contains "iphone"/"ipad"/"android" -> `.phone`/`.tablet`
3. Hostname contains "macbook"/"laptop" -> `.laptop`
4. Bonjour `_printer._tcp` -> `.printer`
5. Bonjour `_raop._tcp` or `_airplay._tcp` -> `.speaker`/`.tv`
6. Ports 80+443+53 open -> `.router`
7. Vendor "Sonos" -> `.speaker`; "Roku"/"Samsung"+port 8008 -> `.tv`
8. Vendor "Synology"/"QNAP" -> `.storage`
9. Vendor "Raspberry Pi" -> `.iot`
10. Vendor "Apple" with no other signal -> `.computer`

### Files Changed
- `NetMonitor-macOS/Views/Devices/ProModeRowView.swift` - row layout overhaul
- `NetMonitor-macOS/Views/DevicesView.swift` - header row update
- `Packages/NetMonitorCore/Sources/NetMonitorCore/Services/DeviceTypeInferenceService.swift` - new
- `NetMonitor-macOS/Platform/DeviceDiscoveryCoordinator.swift` - call inference after scan
