# Devices List View - Phase 1 Design

## Overview
Enhanced Devices page for macOS with consumer/pro toggle, replacing current sidebar Devices tab.

## Layout
- **Split view**: List on left (~350px), DeviceDetailView on right when selected
- Two viewing modes: Consumer (cards) and Pro (dense table)

## Consumer Mode
Card-based rows showing:
- Device icon with status indicator
- Device name (custom or hostname or IP)
- Vendor/manufacturer
- IP address
- Connection type icon (WiFi/Ethernet)
- Network band if WiFi (2.4G/5G/6G)
- Gateway badge if applicable

## Pro Mode
High-density table with columns:
- Status indicator (●/○)
- Name
- IP Address
- MAC Address (truncated with tooltip for full)
- Vendor
- Open Ports (count or list)
- Services (Bonjour/discovered)
- Latency (if available)
- Last Seen (relative time)

## UI Components

### Toolbar button (existing
- Scan)
- Network picker (existing)
- Sort menu (existing)
- Filter: Online Only toggle (existing)
- **NEW**: Consumer/Pro toggle pill

### List Row - Consumer
```
┌─────────────────────────────────────────────────────┐
│ [Icon] Device Name           ● Online    192.168.1.5│
│        Vendor                       WiFi 5G         │
└─────────────────────────────────────────────────────┘
```

### List Row - Pro
```
│ ● │ MacBook Pro │ 192.168.1.5 │ AA:BB:CC │ Apple │ 22,80 │ AirPlay │ 2ms │ Just now │
```

## Interactions
- Click row → select device, show in detail pane
- Double-click → open in new window (future)
- Right-click → context menu (existing: copy IP/MAC, ping, port scan, WOL, remove)

## Data Model
Uses existing `LocalDevice` model:
- ipAddress, macAddress, hostname, vendor
- deviceType, status, lastLatency
- isGateway, supportsWakeOnLan
- firstSeen, lastSeen
- openPorts, discoveredServices

## Integration Points
1. **Sidebar**: Replaces current DevicesView at navigation item "devices"
2. **Dashboard Widget**: Header click navigates to this view
3. **DeviceDetailView**: Existing detail pane (will be enhanced in Phase 2)

## Technical Notes
- Use existing SwiftData `@Query` for device list
- Reuse existing DeviceDiscoveryCoordinator for scanning
- Maintain existing search/filter/sort logic, adapt for both modes
- Use NSTableView-like performance for Pro mode with many devices

## Acceptance Criteria
1. Toggle switches between Consumer and Pro modes
2. Consumer mode shows card-style rows with essential info
3. Pro mode shows dense table with all columns
4. Clicking device shows DeviceDetailView in detail pane
5. Search filters work in both modes
6. Sort options work in both modes
7. Scanning indicator overlays correctly
8. Sidebar navigation works correctly
9. Widget header navigation links here
