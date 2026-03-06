# Devices List - Phase 2: Pro Mode Experience

## Overview
Enhanced Pro mode for macOS devices view with full-screen table and detailed device drill-down page, similar to Fing's professional network analysis view.

## Architecture

### Layout Changes
- **Consumer mode**: Remains split view (list left, detail right) - existing behavior
- **Pro mode**: Full-screen table (no split), click navigates to detail page
- Navigation via SwiftUI `NavigationStack` with push navigation

### Components
- `DevicesView.swift` - Modified to handle Pro mode navigation
- `ProDeviceDetailView.swift` - NEW full-page detail view for Pro mode
- `ProModeRowView.swift` - Already created in Phase 1
- `DeviceCardView.swift` - Already created in Phase 1

## Pro Device Detail Page Sections

### 1. Header Section
- Large device icon with status indicator
- Device name (editable)
- IP address prominent
- Vendor/manufacturer
- Device type badge
- Online/Offline status with duration

### 2. Network Details Card
- IP Address (with copy button)
- MAC Address (with copy button)
- Hostname (resolved)
- Subnet/CIDR (if detectable)
- Gateway IP
- DNS Servers (if available)

### 3. Ports & Services Card
- Open ports table: Port | Protocol | Service | State
- Discovered services list with Bonjour/mDNS names
- Last port scan timestamp

### 4. Connection Timeline Card
- First seen date/time
- Last seen date/time
- Online duration this session
- Historical availability % (if tracking over time)

### 5. Latency Statistics Card (if available)
- Current latency
- Min/Max/Avg latency
- Jitter measurement
- Packet loss %

### 6. Hardware Information Card
- MAC Address (full)
- OUI Vendor
- Manufacturer
- Device type
- Serial number (if available)

### 7. Wake on LAN Card
- MAC Address (prominent)
- Broadcast IP
- Port (default 9)
- Status indicator
- Test button

### 8. Actions Card
- Ping (opens sheet)
- Port Scan (opens sheet)
- Traceroute
- Wake on LAN
- Copy All Info

### 9. Notes Card
- Editable notes field
- Last modified timestamp

## Navigation Flow

```
DevicesView (Pro Mode)
    │
    ├── Table row tap
    │       │
    │       └──> ProDeviceDetailView (full page push)
    │                   │
    │                   ├── Back button returns to table
    │                   │
    │                   └── Sheets: Ping, Port Scan
    │
    └── Toolbar: Scan, Filter, Sort (same as before)

DevicesView (Consumer Mode)
    │
    └── Split view (existing behavior unchanged)
```

## UI/UX Guidelines

### Pro Mode Table
- Dense rows with alternating backgrounds
- Sortable columns
- Column resizing
- Horizontal scroll for overflow

### Pro Device Detail
- Card-based layout (one card per section)
- Consistent card styling with macOS theme
- Monospace font for technical data (IPs, MACs, ports)
- Copy buttons on tap for all technical values
- Action buttons clearly visible

### Interactions
- Single click on row: Select and navigate to detail
- Right-click: Context menu (existing)
- Back navigation via standard macOS back button

## Technical Notes

### Data Sources
- LocalDevice model (existing)
- DeviceDiscoveryCoordinator for live data
- SwiftData for persistence
- NetworkProfile for network context

### Navigation
- Use `NavigationStack` in DevicesView for Pro mode
- Push `ProDeviceDetailView` on row tap
- Standard `.navigationDestination` modifier

## Acceptance Criteria

1. **Pro mode full-screen**: Table takes entire panel width
2. **Navigation works**: Click Pro row → detail page pushes
3. **Consumer unchanged**: Split view still works for Consumer mode
4. **Detail page loads**: Shows all 9 sections with device data
5. **Actions work**: Ping, port scan, wake buttons functional
6. **Back navigation**: Returns to table correctly
7. **Build succeeds**: No compilation errors
8. **SwiftLint passes**: No lint violations

## Future Enhancements (Out of Scope)
- Network traffic graphs per device
- Device comparison view
- Bulk actions on multiple devices
- Export device list
