# Enhanced Devices List View - Phase 1 Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace current DevicesView with a Fing-style enhanced list that has Consumer/Pro mode toggle, with device cards that navigate to detail view.

**Architecture:** Create a new `DevicesListView.swift` with toggle between two presentation modes: Consumer (cards) and Pro (dense table). Reuse existing `DeviceDetailView.swift` for the detail pane. Add `ViewMode` enum to track state.

**Tech Stack:** SwiftUI, SwiftData, existing MacTheme styling

---

## File Structure

- **Modify:** `NetMonitor-macOS/Views/DevicesView.swift` — Replace with new enhanced version
- **Modify:** `NetMonitor-macOS/Views/SidebarView.swift` — Update navigation to new DevicesView
- **Modify:** `NetMonitor-macOS/Views/Dashboard/*.swift` — Update widget header navigation

---

## Task 1: Add ViewMode Enum to DevicesView

**Files:**
- Modify: `NetMonitor-macOS/Views/DevicesView.swift:1-10`

- [ ] **Step 1: Add ViewMode enum and state**

Add after the imports and before the `struct DevicesView` definition:

```swift
// MARK: - View Mode

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
```

Add to the `@State` variables at the top of `DevicesView`:

```swift
@State private var viewMode: DeviceViewMode = .consumer
```

- [ ] **Step 2: Commit**

```bash
git add NetMonitor-macOS/Views/DevicesView.swift
git commit -m "feat: add DeviceViewMode enum for consumer/pro toggle"
```

---

## Task 2: Add Consumer Mode Card List

**Files:**
- Modify: `NetMonitor-macOS/Views/DevicesView.swift:143-169`

- [ ] **Step 1: Add consumerModeList computed property**

Add after `filteredDevices` computed property:

```swift
// MARK: - Consumer Mode List (Card-based)

private var consumerModeList: some View {
    ScrollView {
        LazyVStack(spacing: 8) {
            ForEach(filteredDevices) { device in
                DeviceCardView(device: device)
                    .onTapGesture {
                        selectedDevice = device
                    }
            }
        }
        .padding()
    }
}
```

- [ ] **Step 2: Add DeviceCardView struct**

Add after the `DevicesView` struct (before the `#if DEBUG`):

```swift
// MARK: - Device Card View (Consumer Mode)

struct DeviceCardView: View {
    let device: LocalDevice

    var body: some View {
        HStack(spacing: 12) {
            // Status indicator and icon
            ZStack {
                Circle()
                    .fill(device.status == .online ? MacTheme.Colors.success.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 48, height: 48)

                Image(systemName: device.deviceType.iconName)
                    .font(.title3)
                    .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .gray)
            }

            // Device info
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(device.displayName)
                        .font(.headline)
                        .lineLimit(1)

                    if device.isGateway {
                        Text("Gateway")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(MacTheme.Colors.info.opacity(0.2))
                            .foregroundStyle(MacTheme.Colors.info)
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 8) {
                    Text(device.ipAddress)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if let vendor = device.vendor {
                        Text("·")
                            .foregroundStyle(.tertiary)
                        Text(vendor)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer()

            // Connection info
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(device.status == .online ? MacTheme.Colors.success : Color.gray)
                        .frame(width: 8, height: 8)

                    Text(device.status == .online ? "Online" : "Offline")
                        .font(.caption)
                        .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .secondary)
                }

                if let latency = device.lastLatency {
                    Text(latencyText(latency))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(selectedDevice?.id == device.id ? Color.accentColor : Color.clear, lineWidth: 2)
        )
    }

    private func latencyText(_ latency: Double) -> String {
        if latency < 1 { return "<1 ms" }
        return String(format: "%.0f ms", latency)
    }
}
```

- [ ] **Step 3: Replace list in body with conditional**

Modify the `deviceList` computed property (around line 143) to use conditional:

```swift
private var deviceList: some View {
    Group {
        if filteredDevices.isEmpty && coordinator?.isScanning != true {
            ContentUnavailableView(
                "No Devices Found",
                systemImage: "network",
                description: Text("Click Scan to discover devices on your network")
            )
            .accessibilityIdentifier("devices_label_empty")
        } else {
            if viewMode == .consumer {
                consumerModeList
            } else {
                proModeList
            }
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
git commit -m "feat: add consumer mode card list to DevicesView"
```

---

## Task 3: Add Pro Mode Table View

**Files:**
- Modify: `NetMonitor-macOS/Views/DevicesView.swift`

- [ ] **Step 1: Add proModeList computed property**

Add after `consumerModeList`:

```swift
// MARK: - Pro Mode List (Dense Table)

private var proModeList: some View {
    ScrollView {
        LazyVStack(spacing: 0) {
            // Header row
            proModeHeaderRow

            Divider()

            // Data rows
            ForEach(filteredDevices) { device in
                ProModeRowView(device: device)
                    .onTapGesture {
                        selectedDevice = device
                    }
                Divider()
            }
        }
    }
}

private var proModeHeaderRow: some View {
    HStack(spacing: 0) {
        Text("Status")
            .frame(width: 50, alignment: .center)
        Text("Name")
            .frame(minWidth: 120, alignment: .leading)
        Text("IP Address")
            .frame(width: 100, alignment: .leading)
        Text("MAC")
            .frame(width: 100, alignment: .leading)
        Text("Vendor")
            .frame(minWidth: 80, alignment: .leading)
        Text("Ports")
            .frame(width: 80, alignment: .center)
        Text("Services")
            .frame(minWidth: 100, alignment: .leading)
        Text("Latency")
            .frame(width: 60, alignment: .trailing)
        Text("Last Seen")
            .frame(width: 80, alignment: .trailing)
    }
    .font(.caption)
    .fontWeight(.semibold)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(Color.gray.opacity(0.1))
}
```

- [ ] **Step 2: Add ProModeRowView struct**

Add after `DeviceCardView`:

```swift
// MARK: - Pro Mode Row View

struct ProModeRowView: View {
    let device: LocalDevice

    var body: some View {
        HStack(spacing: 0) {
            // Status
            Circle()
                .fill(device.status == .online ? MacTheme.Colors.success : Color.gray)
                .frame(width: 8, height: 8)
                .frame(width: 50, alignment: .center)

            // Name
            Text(device.displayName)
                .lineLimit(1)
                .frame(minWidth: 120, alignment: .leading)

            // IP
            Text(device.ipAddress)
                .fontDesign(.monospaced)
                .font(.caption)
                .frame(width: 100, alignment: .leading)

            // MAC
            Text(device.macAddress.isEmpty ? "-" : String(device.macAddress.suffix(8)))
                .fontDesign(.monospaced)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)

            // Vendor
            Text(device.vendor ?? "-")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 80, alignment: .leading)

            // Ports
            let ports = device.openPorts ?? []
            Text(ports.isEmpty ? "-" : "\(ports.prefix(3).map(String.init).joined(separator: ",")))")
                .font(.caption)
                .foregroundStyle(ports.isEmpty ? .secondary : MacTheme.Colors.info)
                .frame(width: 80, alignment: .center)

            // Services
            let services = device.discoveredServices ?? []
            Text(services.isEmpty ? "-" : "\(services.prefix(2).joined(separator: ", ")))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(minWidth: 100, alignment: .leading)

            // Latency
            if let latency = device.lastLatency {
                Text(latency < 1 ? "<1ms" : String(format: "%.0fms", latency))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            } else {
                Text("-")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 60, alignment: .trailing)
            }

            // Last Seen
            Text(lastSeenText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private var lastSeenText: String {
        let interval = Date().timeIntervalSince(device.lastSeen)
        if interval < 60 { return "Now" }
        if interval < 3600 { return "\(Int(interval/60))m" }
        if interval < 86400 { return "\(Int(interval/3600))h" }
        return "\(Int(interval/86400))d"
    }
}
```

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-macOS/Views/DevicesView.swift
git commit -m "feat: add pro mode dense table to DevicesView"
```

---

## Task 4: Add View Mode Toggle to Toolbar

**Files:**
- Modify: `NetMonitor-macOS/Views/DevicesView.swift:197-285`

- [ ] **Step 1: Add Picker to toolbar**

Find the `toolbarContent` computed property and add a new `ToolbarItemGroup` after the Sort menu:

```swift
ToolbarItemGroup(placement: .automatic) {
    Picker("View", selection: $viewMode) {
        ForEach(DeviceViewMode.allCases, id: \.self) { mode in
            Label(mode.rawValue, systemImage: mode.icon)
                .tag(mode)
        }
    }
    .pickerStyle(.segmented)
    .frame(width: 180)
    .accessibilityIdentifier("devices_picker_viewMode")
}
```

- [ ] **Step 2: Commit**

```bash
git add NetMonitor-macOS/Views/DevicesView.swift
git commit -m "feat: add consumer/pro toggle to toolbar"
```

---

## Task 5: Update Sidebar Navigation

**Files:**
- Modify: `NetMonitor-macOS/Views/SidebarView.swift`

- [ ] **Step 1: Find sidebar navigation**

Search for where DevicesView is used in navigation:

```bash
grep -n "DevicesView" NetMonitor-macOS/Views/SidebarView.swift
```

- [ ] **Step 2: Verify navigation is correct**

The existing `DevicesView` should already be connected. No changes needed if navigation works. If needed, ensure `NavigationLink` destination is correct.

- [ ] **Step 3: Commit**

```bash
git add NetMonitor-macOS/Views/SidebarView.swift
git commit -m "chore: verify sidebar navigation for DevicesView"
```

---

## Task 6: Build and Test

**Files:**
- Test: `NetMonitor-macOS`

- [ ] **Step 1: Build project**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -30
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify view mode toggle works**

Check that:
- Consumer mode shows card-based list
- Pro mode shows dense table
- Toggle switches between modes
- Click on device shows detail pane

- [ ] **Step 3: Commit**

```bash
git commit -m "build: verify Phase 1 implementation compiles"
```

---

## Summary

After these tasks:
- DevicesView has Consumer/Pro toggle in toolbar
- Consumer mode shows card-based rows with device info
- Pro mode shows dense table with all columns
- Click on device shows DeviceDetailView in right pane
- Sidebar navigation works correctly
