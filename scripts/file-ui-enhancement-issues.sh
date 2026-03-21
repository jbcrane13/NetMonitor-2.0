#!/bin/bash
# File retroactive GitHub issues for the March 2026 UI Enhancement pass.
# Run from repo root on a machine with `gh` authenticated.
# All issues are created and immediately closed since the work is done.

set -e

LABEL="enhancement"
MILESTONE=""  # set to milestone name if you have one

# Ensure label exists
gh label create "$LABEL" --description "Feature improvements" --color "a2eeef" 2>/dev/null || true

file_and_close() {
    local title="$1"
    local body="$2"
    echo "Filing: $title"
    local url
    url=$(gh issue create --title "$title" --body "$body" --label "$LABEL" 2>&1)
    local num
    num=$(echo "$url" | grep -oE '[0-9]+$')
    gh issue close "$num" --comment "Completed as part of the March 2026 UI polish pass."
    echo "  -> $url (closed)"
}

# 1. MiniSparklineView — shared sparkline component
file_and_close \
    "UI: Extract shared MiniSparklineView sparkline component" \
    "$(cat <<'BODY'
## Summary
Extract a reusable sparkline wrapper around `HistorySparkline` (NetMonitorCore) to eliminate duplicated chart code across dashboard cards.

## Changes
- Created `NetMonitor-macOS/Views/Components/MiniSparklineView.swift`
- Supports threshold-based coloring, dual data overlays, configurable height/pulse/corner radius
- Adopted by ISPHealthCard (dual-overlay throughput), WiFiSignalCard (RSSI history), DeviceCardView (per-device latency), MenuBarPopoverView (gateway latency)
- Replaced inline `ZStack` + dual `HistorySparkline` in ISPHealthCard with single `MiniSparklineView`
- Removed `import Charts` and Swift Charts `LineMark`/`AreaMark` from WiFiSignalCard

## Files Modified
- `NetMonitor-macOS/Views/Components/MiniSparklineView.swift` (new)
- `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift`
- `NetMonitor-macOS/Views/Dashboard/WiFiSignalCard.swift`
BODY
)"

# 2. CardStateViews — loading/empty/error skeleton states
file_and_close \
    "UI: Add skeleton loading/empty/error states for dashboard cards" \
    "$(cat <<'BODY'
## Summary
Replace bare `ProgressView()` loading states with polished skeleton views across all dashboard cards.

## Changes
- Created `NetMonitor-macOS/Views/Components/CardStateViews.swift`
- Includes ShimmerModifier, SkeletonBar, SkeletonCircle, CardLoadingSkeleton, CardEmptyState, CardErrorState, CardStateView
- Adopted by ISPHealthCard, WiFiSignalCard, NetworkIntelCard

## Files Modified
- `NetMonitor-macOS/Views/Components/CardStateViews.swift` (new)
- `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift`
- `NetMonitor-macOS/Views/Dashboard/WiFiSignalCard.swift`
- `NetMonitor-macOS/Views/Dashboard/NetworkIntelCard.swift`
BODY
)"

# 3. Tool categories on both platforms
file_and_close \
    "UI: Categorize tools into Diagnostics/Discovery/Monitoring/Actions" \
    "$(cat <<'BODY'
## Summary
Group tools into logical categories instead of a flat grid for better discoverability.

## Changes
- macOS: Added `ToolCategory` enum with 4 cases, rewrote `ToolsView` with `LazyVStack` section headers
- iOS: Added `IOSToolCategory` enum (slightly different tool set — includes Network Monitor, Room Scanner, Web Browser)
- Both platforms render categorized sections with icons and uppercase labels

## Files Modified
- `NetMonitor-macOS/Views/ToolsView.swift`
- `NetMonitor-iOS/Views/Tools/ToolsView.swift`
BODY
)"

# 4. Sortable pro mode columns
file_and_close \
    "UI: Add sortable column headers to pro mode device table" \
    "$(cat <<'BODY'
## Summary
Make pro mode column headers clickable for sorting with directional chevrons.

## Changes
- Added `vendor` and `latency` cases to `DeviceSortOrder` enum
- Added `sortAscending: Bool` state with smart defaults (lastSeen descending, others ascending)
- `sortableHeader()` helper renders clickable column headers with directional chevrons
- Extended `filteredDevices` sort logic with ascending/descending reversal

## Files Modified
- `NetMonitor-macOS/Views/DevicesView.swift`
BODY
)"

# 5. Device quick actions
file_and_close \
    "UI: Add quick action bar to device detail views" \
    "$(cat <<'BODY'
## Summary
Add a row of quick-action pill buttons between header and network info in device detail.

## Changes
- macOS: Added `quickActionBar` with Ping, Scan Ports, Wake (conditional), Copy IP (NSPasteboard), Monitor
- iOS: Added `quickActionBar` with NavigationLinks for Ping, Scan, DNS, Wake + Button for Copy IP (UIPasteboard)
- Both use tinted pill button style

## Files Modified
- `NetMonitor-macOS/Views/DeviceDetailView.swift`
- `NetMonitor-iOS/Views/DeviceDetail/DeviceDetailView.swift`
BODY
)"

# 6. Per-device latency sparklines
file_and_close \
    "UI: Add per-device latency sparklines to DeviceCardView" \
    "$(cat <<'BODY'
## Summary
Show inline latency history sparklines on each device card using the transient history buffer.

## Changes
- Added `@Transient public var latencyHistory: [Double]` to `LocalDevice` (max 20 samples, in-memory only)
- Updated `updateLatency()` to append to history buffer
- `DeviceCardView` renders `MiniSparklineView` when `latencyHistory.count > 1`
- Uses threshold coloring via `MacTheme.Colors.latencyColor`

## Files Modified
- `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/LocalDevice.swift`
- `NetMonitor-macOS/Views/Devices/DeviceCardView.swift`
BODY
)"

# 7. Responsive dashboard layout
file_and_close \
    "UI: Add responsive 3-breakpoint dashboard layout" \
    "$(cat <<'BODY'
## Summary
Make the war room dashboard reflow based on window width.

## Changes
- Added `DashboardLayout` enum: `.compact` (<1200pt), `.standard` (1200–1599pt), `.wide` (≥1600pt)
- Top row (Gateway Health + Health Gauge) always anchored at top across all breakpoints
- Extracted `diagnosticsStack(gap:)` helper shared across all three layouts
- Compact mode uses single-column scroll; wide mode gives diagnostics and devices more room

## Files Modified
- `NetMonitor-macOS/Views/NetworkDetailView.swift`
BODY
)"

# 8. Menu bar popover depth
file_and_close \
    "UI: Add latency sparkline, quick actions, and problem devices to menu bar popover" \
    "$(cat <<'BODY'
## Summary
Enrich the menu bar popover with more actionable information.

## Changes
- Added gateway latency sparkline section (MiniSparklineView with threshold coloring)
- Added quick action buttons (Scan, Ping, Speed)
- Added problem devices section (up to 3 offline or >100ms devices with ATTENTION header)
- Reduced target list maxHeight to 140 to keep popover height reasonable

## Files Modified
- `NetMonitor-macOS/MenuBar/MenuBarPopoverView.swift`
BODY
)"

# 9. Keyboard shortcuts
file_and_close \
    "UI: Add keyboard shortcuts (⌘1-4, ⌘R, ⌘K, ⌘T)" \
    "$(cat <<'BODY'
## Summary
Add power-user keyboard shortcuts for sidebar navigation and quick actions.

## Changes
- ⌘1 Jump to active network, ⌘2 Devices, ⌘3 Tools, ⌘4 Settings
- ⌘R Rescan network, ⌘K Quick jump to device, ⌘T Quick tool launch
- Extracted `KeyboardShortcutsModifier` as standalone ViewModifier to avoid Swift type-checker timeout
- Created `QuickJumpSheet` — Spotlight-style device search overlay (filters by name, IP, vendor, hostname)

## Files Modified
- `NetMonitor-macOS/Views/ContentView.swift`
- `NetMonitor-macOS/Views/Components/QuickJumpSheet.swift` (new)
BODY
)"

# 10. iPad sidebar polish
file_and_close \
    "UI: Polish iPad sidebar with network status and selection indicators" \
    "$(cat <<'BODY'
## Summary
Apply macOS sidebar visual treatment to the iPad NavigationSplitView.

## Changes
- Structured `iPadSidebar` with NETWORK and NAVIGATE sections
- NETWORK section shows active network name, ACTIVE badge, device count, gateway latency with threshold coloring
- NAVIGATE section has accent-colored selection indicator bar and category count badge on Tools
- Added `connectionTypeIcon`, `networkName`, `gatewayLatency` computed properties to `DashboardViewModel`

## Files Modified
- `NetMonitor-iOS/Views/ContentView.swift`
- `NetMonitor-iOS/ViewModels/DashboardViewModel.swift`
BODY
)"

echo ""
echo "✅ All 10 issues filed and closed."
