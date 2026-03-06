# Devices Pro Mode - Phase 2 Design

## Overview

Phase 2 completes the Fing-style Pro mode experience with full-screen dense table and enhanced Pro-level device detail page.

## Phase 1 Recap

- Consumer/Pro toggle in toolbar
- Consumer mode: Card-based list with split view detail pane
- Pro mode: Dense table (same split view)

## Phase 2 Changes

### 1. Pro Mode Layout Change

**Current (Phase 1):**
- Both modes use split view (list left, detail right)

**Phase 2:**
- **Consumer mode**: Keep existing split view
- **Pro mode**: Full-screen table, no split, click navigates to detail page

### 2. Navigation Flow

```
Consumer Mode:                    Pro Mode:
┌─────────────────┬──────────┐  ┌─────────────────────────────┐
│ Device List     │ Detail   │  │ Device Table (full width)   │
│ (cards)        │ Pane     │  │                             │
│                 │          │  │ Click → Navigation Push    │
│                 │          │  │        ↓                   │
└─────────────────┴──────────┘  │ ProDeviceDetailView        │
                                 │ (full page)               │
                                 └─────────────────────────────┘
```

### 3. New ProDeviceDetailView

Enhanced full-page view with Pro-level detail sections:

#### Section 1: Header
- Large device icon with status indicator
- Device name (editable)
- Custom type badge
- Vendor/manufacturer
- Online/Offline status with duration

#### Section 2: Network Details (Expanded)
- IP Address (IPv4)
- MAC Address (with copy button)
- Hostname (if resolved)
- Subnet mask
- Gateway IP
- DNS servers (if available)

#### Section 3: Ports & Services
- Open ports table: Port | Protocol | Service | State
- Discovered services list with Bonjour details
- Last port scan timestamp

#### Section 4: Connection Timeline
- First seen date/time
- Last seen date/time
- Online duration this session
- Total time tracked
- Online/offline history chart (if available)

#### Section 5: Latency Statistics
- Current latency
- Min/Max/Avg latency
- Jitter (if available)
- Packet loss percentage
- Historical latency chart

#### Section 6: Hardware Info
- MAC Address (full)
- OUI Prefix / Vendor lookup
- Manufacturer
- Device type (editable)
- Supports Wake on LAN flag

#### Section 7: Wake on LAN
- MAC Address (prominent)
- Broadcast IP
- Port (default 9)
- SecureOn password (if set)
- Test/Execute button

#### Section 8: Actions
- Ping (opens sheet)
- Port Scan (opens sheet)
- Traceroute
- Copy IP/MAC
- Add to Targets

#### Section 9: Notes
- Editable notes field
- Timestamps for edits

## Technical Implementation

### Files Modified
- `DevicesView.swift` - Update navigation logic for Pro mode
- `DeviceDetailView.swift` - Minor tweaks (reuse existing)

### Files Created
- `ProDeviceDetailView.swift` - New enhanced detail page
- `ProModeRowView.swift` - Already exists from Phase 1

### Navigation Pattern
- Use SwiftUI `NavigationStack` with `NavigationLink`
- Pro mode: `navigationDestination` for device detail
- Pass device via `NavigationLink(value:)` pattern

### Data Access
- Use existing `LocalDevice` model from SwiftData
- Lazy load expensive data (Bonjour, port history)
- Cache network lookup results

## Acceptance Criteria

1. ✅ Pro mode shows full-screen table (no split)
2. ✅ Clicking Pro mode row navigates to full detail page
3. ✅ Consumer mode retains split view behavior
4. ✅ ProDeviceDetailView shows all 9 sections
5. ✅ Back navigation returns to Pro table
6. ✅ All existing actions (ping, port scan, WOL) work
7. ✅ Edit device name/type/notes works
8. ✅ Build succeeds with SwiftLint passing
