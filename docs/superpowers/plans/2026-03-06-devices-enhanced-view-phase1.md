# Enhanced Devices List View (Phase 1) Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace current macOS DevicesView with enhanced list showing Consumer/Pro toggle modes, similar to Fing device view

**Architecture:** Modify existing DevicesView with new view mode toggle, add ProTableView component for dense display. Maintains split-view with DeviceDetailView in detail pane.

**Tech Stack:** SwiftUI, existing MacTheme, LocalDevice model, DeviceDiscoveryCoordinator

---

## File Structure

### Files to Modify
- `NetMonitor-macOS/Views/DevicesView.swift` - Main view with toggle logic
- `NetMonitor-macOS/Views/DeviceRowView.swift` - Consumer mode row component
- `NetMonitor-macOS/Views/SidebarView.swift` - Update sidebar navigation
- `NetMonitor-macOS/Views/Dashboard/DashboardView.swift` - Update widget navigation (if exists)

### New Files to Create
- `NetMonitor-macOS/Views/Devices/DevicesProTableView.swift` - Pro mode dense table

---

## Tasks

### Task 1: Add View Mode State to DevicesView

**Files:**
- Modify: `NetMonitor-macOS/Views/DevicesView.swift:1-20`

- [ ] **Step 1: Add view mode enum and state**

Add after existing state properties (around line 16):

```swift
enum DeviceViewMode: String, CaseIterable {
    case consumer = "Consumer"
    case pro = "Pro"

    var icon: String {
        switch self {
        case .consumer: return "square.grid.2x2"
        case .pro: return "list.bullet"
        }
    }
}

@State private var viewMode: DeviceViewMode = .consumer
```

- [ ] **Step 2: Add toggle to toolbar**

In toolbarContent (around line 197), add after existing toolbar items:

```swift
ToolbarItem(placement: .automatic) {
    Picker("View Mode", selection: $viewMode) {
        ForEach(DeviceViewMode.allCases, id: \.self) { mode in
            Label(mode.rawValue, systemImage: mode.icon)
                .tag(mode)
        }
    }
    .pickerStyle(.segmented)
    .frame(width: 150)
}
```

- [ ] **Step 3: Add conditional list rendering**

In deviceList computed property (around line 143), wrap List in conditional:

```swift
private var deviceList: some View {
    Group {
        switch viewMode {
        case .consumer:
            consumerListView
        case .pro:
            proListView
        }
    }
    .overlay {
        if coordinator?.isScanning == true {
            scanningOverlay
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add NetMonitor-macOS/Views/DevicesView.swift
git commit -m "feat(macOS): Add Consumer/Pro view mode toggle to DevicesView"
```

---

### Task 2: Create Consumer List View

**Files:**
- Modify: `NetMonitor-macOS/Views/DevicesView.swift:141-169`

- [ ] **Step 1: Create consumerListView computed property**

Add after the deviceList property:

```swift
private var consumerListView: some View {
    Group {
        if filteredDevices.isEmpty && coordinator?.isScanning != true {
            ContentUnavailableView(
                "No Devices Found",
                systemImage: "network",
                description: Text("Click Scan to discover devices on your network")
            )
            .accessibilityIdentifier("devices_label_empty")
        } else {
            List(filteredDevices, selection: $selectedDevice) { device in
                DeviceRowView(device: device)
                    .tag(device)
                    .contextMenu {
                        deviceContextMenu(for: device)
                    }
            }
            .listStyle(.inset)
            .accessibilityIdentifier("devices_list")
        }
    }
}
```

- [ ] **Step 2: Create proListView placeholder**

Add after consumerListView:

```swift
private var proListView: some View {
    DevicesProTableView(
        devices: filteredDevices,
        selectedDevice: $selectedDevice,
        onContextMenu: deviceContextMenu
    )
}
```

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-macOS/Views/DevicesView.swift
git commit -m "feat(macOS): Add consumer list view to DevicesView"
```

---

### Task 3: Create Pro Table View Component

**Files:**
- Create: `NetMonitor-macOS/Views/Devices/DevicesProTableView.swift`

- [ ] **Step 1: Create the ProTableView file**

```swift
import SwiftUI
import NetMonitorCore

struct DevicesProTableView: View {
    let devices: [LocalDevice]
    @Binding var selectedDevice: LocalDevice?
    var onContextMenu: (LocalDevice) -> some View

    var body: some View {
        Group {
            if devices.isEmpty {
                ContentUnavailableView(
                    "No Devices Found",
                    systemImage: "network",
                    description: Text("Click Scan to discover devices on your network")
                )
            } else {
                Table(devices, selection: $selectedDevice) {
                    TableColumn("Status") { device in
                        statusView(for: device)
                    }
                    .width(40)

                    TableColumn("Name", value: \.displayName) { device in
                        Text(device.displayName)
                            .fontWeight(.medium)
                    }
                    .width(min: 100, ideal: 150)

                    TableColumn("IP Address", value: \.ipAddress) { device in
                        Text(device.ipAddress)
                            .fontDesign(.monospaced)
                    }
                    .width(80)

                    TableColumn("MAC") { device in
                        Text(device.macAddress.isEmpty ? "-" : device.macAddress)
                            .fontDesign(.monospaced)
                            .foregroundStyle(.secondary)
                    }
                    .width(80)

                    TableColumn("Vendor") { device in
                        Text(device.vendor ?? "-")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .width(min: 80, ideal: 120)

                    TableColumn("Ports") { device in
                        if let ports = device.openPorts, !ports.isEmpty {
                            Text(ports.prefix(3).map(String.init).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("-")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .width(60)

                    TableColumn("Services") { device in
                        if let services = device.discoveredServices, !services.isEmpty {
                            Text(services.prefix(2).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("-")
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .width(80)

                    TableColumn("Latency") { device in
                        Text(device.latencyText ?? "-")
                            .fontDesign(.monospaced)
                            .foregroundStyle(device.lastLatency != nil ? .primary : .tertiary)
                    }
                    .width(50)

                    TableColumn("Last Seen") { device in
                        Text(relativeTime(from: device.lastSeen))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 80)
                }
                .tableStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
    }

    @ViewBuilder
    private func statusView(for device: LocalDevice) -> some View {
        Circle()
            .fill(device.status == .online ? MacTheme.Colors.success : Color.gray.opacity(0.5))
            .frame(width: 10, height: 10)
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        return "\(Int(interval / 86400))d ago"
    }
}

#Preview {
    DevicesProTableView(
        devices: [],
        selectedDevice: .constant(nil),
        onContextMenu: { _ in EmptyView() }
    )
}
```

- [ ] **Step 2: Create directory if needed and save file**

- [ ] **Step 3: Build to verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -30
```

- [ ] **Step 4: Commit**

```bash
git add NetMonitor-macOS/Views/Devices/DevicesProTableView.swift
git commit -m "feat(macOS): Add Pro table view for devices"
```

---

### Task 4: Update Sidebar Navigation

**Files:**
- Modify: `NetMonitor-macOS/Views/SidebarView.swift`

- [ ] **Step 1: Find Devices navigation item**

Read SidebarView.swift and find where DevicesView is referenced in navigation

- [ ] **Step 2: Verify it points to existing DevicesView**

The existing navigation should work - verify it uses `DevicesView()` and no changes needed

- [ ] **Step 3: Commit if changed**

---

### Task 5: Update Widget Navigation (if needed)

**Files:**
- Modify: Check `NetMonitor-macOS/Views/Dashboard/` for widget files

- [ ] **Step 1: Find Dashboard widget files**

```bash
ls NetMonitor-macOS/Views/Dashboard/
```

- [ ] **Step 2: Find where devices widget is defined**

Search for DevicesCard or similar

- [ ] **Step 3: Update header tap navigation**

If widget exists with header tap → change to navigate to DevicesView()

- [ ] **Step 4: Commit**

---

### Task 6: Final Build and Verification

**Files:**
- All modified

- [ ] **Step 1: Full build**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify SwiftLint passes**

```bash
swiftlint lint NetMonitor-macOS/Views/Devices/ 2>&1 || true
```

- [ ] **Step 3: Final commit**

```bash
git add -A && git commit -m "feat(macOS): Complete Phase 1 Devices enhanced view

- Add Consumer/Pro view mode toggle
- Create Pro table view with dense device info
- Consumer mode shows card-based list
- Pro mode shows table with MAC, vendor, ports, services, latency

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Dependencies

- LocalDevice model already has: ipAddress, macAddress, vendor, openPorts, discoveredServices, lastLatency, lastSeen, status, displayName
- DeviceDiscoveryCoordinator provides: isScanning, scanProgress, lastScanTime
- Existing MacTheme.Colors.success for status indicators
- Existing DeviceRowView for consumer mode

## Testing Notes

- Consumer mode: Verify card layout matches existing DeviceRowView
- Pro mode: Verify table columns display all data correctly
- Toggle: Verify switching modes preserves selected device and scroll position
- Navigation: Verify sidebar and widget link to enhanced DevicesView

---

**Ready to execute? Say: "Execute the plan at `docs/superpowers/plans/2026-03-06-devices-enhanced-view-phase1.md` using subagent-driven-development."**
