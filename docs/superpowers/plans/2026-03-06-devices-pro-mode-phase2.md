# Devices Pro Mode - Phase 2 Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Pro mode experience with full-screen table and enhanced device detail page

**Architecture:** Pro mode gets full-screen table (no split view). Click navigates to new ProDeviceDetailView. Consumer mode keeps existing split view behavior.

**Tech Stack:** SwiftUI, SwiftData, existing MacTheme styling

---

## File Structure

- **Modify:** `NetMonitor-macOS/Views/DevicesView.swift` — Update Pro mode navigation
- **Create:** `NetMonitor-macOS/Views/Devices/ProDeviceDetailView.swift` — New enhanced detail page

---

## Task 1: Modify DevicesView for Pro Mode Navigation

**Files:**
- Modify: `NetMonitor-macOS/Views/DevicesView.swift`

### Context

Current DevicesView has:
- Split view: list left, detail right
- Both Consumer and Pro modes use the same split layout

Need to change:
- Consumer mode: Keep split view (existing behavior)
- Pro mode: Full-screen table, click navigates to detail page

### Implementation

- [ ] **Step 1: Read current DevicesView structure**

Read `DevicesView.swift` to understand the current body layout and navigation pattern.

- [ ] **Step 2: Wrap body in NavigationStack**

Wrap the content in `NavigationStack` to enable navigation:

```swift
var body: some View {
    NavigationStack {
        // existing content
    }
}
```

- [ ] **Step 3: Modify Pro mode to use NavigationLink**

In the `proModeList` computed property, wrap rows in `NavigationLink` destination:

```swift
ForEach(filteredDevices) { device in
    NavigationLink(value: device) {
        ProModeRowView(device: device, isSelected: selectedDevice?.id == device.id)
    }
    .buttonStyle(.plain)
}
```

- [ ] **Step 4: Add navigationDestination for Pro mode**

Add after the main content:

```swift
.navigationDestination(for: LocalDevice.self) { device in
    ProDeviceDetailView(device: device)
}
```

- [ ] **Step 5: Keep Consumer mode as split view**

Consumer mode should continue to use the existing split view with `selectedDevice` binding. The conditional rendering should:
- Consumer: Use existing split view pattern
- Pro: Use NavigationStack with navigationDestination

- [ ] **Step 6: Build and verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

- [ ] **Step 7: Commit**

```bash
git add NetMonitor-macOS/Views/DevicesView.swift
git commit -m "feat(macOS): Add Pro mode full-screen navigation to DevicesView

- Add NavigationStack for Pro mode navigation
- Consumer mode retains split view behavior
- Click Pro row navigates to detail page

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Create ProDeviceDetailView

**Files:**
- Create: `NetMonitor-macOS/Views/Devices/ProDeviceDetailView.swift`

### Implementation

- [ ] **Step 1: Create ProDeviceDetailView file**

Create new file with comprehensive Pro-level detail view:

```swift
import SwiftUI
import SwiftData
import NetMonitorCore

struct ProDeviceDetailView: View {
    @Bindable var device: LocalDevice
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isEditing = false
    @State private var editedName: String = ""
    @State private var editedNotes: String = ""
    @State private var selectedDeviceType: DeviceType = .unknown

    // Sheet states
    @State private var showPingSheet = false
    @State private var showPortScanSheet = false
    @State private var wolAction = WakeOnLanAction()

    // Loaded data
    @State private var bonjourServices: [String] = []
    @State private var latencyHistory: [Double] = []

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                networkDetailsSection
                portsAndServicesSection
                latencyStatsSection
                hardwareSection
                wakeOnLanSection
                timelineSection
                notesSection
                actionsSection
            }
            .padding()
        }
        .navigationTitle(device.displayName)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(isEditing ? "Done" : "Edit") {
                    if isEditing { saveChanges() }
                    else { startEditing() }
                    isEditing.toggle()
                }
            }
        }
        .task { await loadData() }
        .wakeOnLanAlert(wolAction)
        .sheet(isPresented: $showPingSheet) {
            DevicePingSheet(device: device, isPresented: $showPingSheet)
        }
        .sheet(isPresented: $showPortScanSheet) {
            DevicePortScanSheet(device: device, isPresented: $showPortScanSheet)
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(device.status == .online ? MacTheme.Colors.success.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)

                Image(systemName: device.deviceType.iconName)
                    .font(.largeTitle)
                    .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .gray)
            }

            VStack(alignment: .leading, spacing: 4) {
                if isEditing {
                    TextField("Device Name", text: $editedName)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Text(device.displayName)
                        .font(.title)
                        .fontWeight(.bold)
                }

                HStack(spacing: 8) {
                    Circle()
                        .fill(device.status == .online ? MacTheme.Colors.success : Color.gray)
                        .frame(width: 10, height: 10)

                    Text(device.status == .online ? "Online" : "Offline")
                        .font(.headline)
                        .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .secondary)

                    if device.status == .online, let latency = device.lastLatency {
                        Text("•")
                            .foregroundStyle(.secondary)
                        Text(latencyText(latency))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                if let vendor = device.vendor {
                    Text(vendor)
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                }

                if device.isGateway {
                    Text("Gateway")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(MacTheme.Colors.info.opacity(0.2))
                        .foregroundStyle(MacTheme.Colors.info)
                        .clipShape(Capsule())
                }
            }

            Spacer()

            if isEditing {
                Picker("Type", selection: $selectedDeviceType) {
                    ForEach(DeviceType.allCases, id: \.self) { type in
                        Label(type.rawValue.capitalized, systemImage: type.iconName)
                            .tag(type)
                    }
                }
                .labelsHidden()
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Network Details Section

    private var networkDetailsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Network Details", systemImage: "network")
                .font(.headline)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("IP Address")
                        .foregroundStyle(.secondary)
                    Text(device.ipAddress)
                        .fontDesign(.monospaced)
                        .textSelection(.enabled)
                }

                GridRow {
                    Text("MAC Address")
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(device.macAddress.isEmpty ? "-" : device.macAddress)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)

                        if !device.macAddress.isEmpty {
                            Button {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(device.macAddress, forType: .string)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        }
                    }
                }

                if let hostname = device.hostname, !hostname.isEmpty {
                    GridRow {
                        Text("Hostname")
                            .foregroundStyle(.secondary)
                        Text(hostname)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                    }
                }

                if let resolved = device.resolvedHostname, !resolved.isEmpty {
                    GridRow {
                        Text("Resolved")
                            .foregroundStyle(.secondary)
                        Text(resolved)
                            .fontDesign(.monospaced)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Ports & Services Section

    private var portsAndServicesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Ports & Services", systemImage: "server.rack")
                .font(.headline)

            Divider()

            if let ports = device.openPorts, !ports.isEmpty {
                Text("Open Ports: \(ports.sorted().map(String.init).joined(separator: ", ")))")
                    .font(.subheadline)
                    .foregroundStyle(MacTheme.Colors.info)
            } else {
                Text("No open ports detected")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
            }

            if let services = device.discoveredServices, !services.isEmpty {
                Divider()
                Text("Discovered Services:")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                FlowLayout(spacing: 8) {
                    ForEach(services, id: \.self) { service in
                        Text(service)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(MacTheme.Colors.info.opacity(0.1))
                            .foregroundStyle(MacTheme.Colors.info)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Latency Stats Section

    private var latencyStatsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Latency Statistics", systemImage: "waveform.path")
                .font(.headline)

            Divider()

            HStack(spacing: 24) {
                latencyStatItem(title: "Current", value: device.lastLatency.map(latencyText) ?? "-")
                latencyStatItem(title: "Min", value: "-")
                latencyStatItem(title: "Max", value: "-")
                latencyStatItem(title: "Avg", value: "-")
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    private func latencyStatItem(title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .fontDesign(.monospaced)
        }
    }

    // MARK: - Hardware Section

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Hardware", systemImage: "cpu")
                .font(.headline)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("Manufacturer")
                        .foregroundStyle(.secondary)
                    Text(device.vendor ?? "Unknown")
                }

                GridRow {
                    Text("Device Type")
                        .foregroundStyle(.secondary)
                    Label(device.deviceType.rawValue.capitalized, systemImage: device.deviceType.iconName)
                }

                GridRow {
                    Text("Supports WOL")
                        .foregroundStyle(.secondary)
                    Text(device.supportsWakeOnLan ? "Yes" : "No")
                        .foregroundStyle(device.supportsWakeOnLan ? MacTheme.Colors.success : .secondary)
                }

                if !device.macAddress.isEmpty {
                    GridRow {
                        Text("OUI")
                            .foregroundStyle(.secondary)
                        Text(String(device.macAddress.replacingOccurrences(of: ":", with: "").prefix(6)))
                            .fontDesign(.monospaced)
                    }
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Wake on LAN Section

    private var wakeOnLanSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Wake on LAN", systemImage: "power")
                .font(.headline)

            Divider()

            if device.supportsWakeOnLan && !device.macAddress.isEmpty {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("MAC Address")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(device.macAddress)
                            .fontDesign(.monospaced)
                    }

                    Spacer()

                    Button {
                        Task {
                            await wolAction.wake(device: device)
                        }
                    } label: {
                        Label("Wake", systemImage: "power")
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                Text("Wake on LAN not supported")
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Timeline", systemImage: "clock")
                .font(.headline)

            Divider()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text("First Seen")
                        .foregroundStyle(.secondary)
                    Text(device.firstSeen.formatted(date: .abbreviated, time: .shortened))
                }

                GridRow {
                    Text("Last Seen")
                        .foregroundStyle(.secondary)
                    Text(device.lastSeen.formatted(date: .abbreviated, time: .shortened))
                }

                GridRow {
                    Text("Time Since Last")
                        .foregroundStyle(.secondary)
                    Text(timeSinceLastSeen)
                }

                GridRow {
                    Text("Total Tracked")
                        .foregroundStyle(.secondary)
                    Text(totalTimeTracked)
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Notes", systemImage: "note.text")
                .font(.headline)

            Divider()

            if isEditing {
                TextEditor(text: $editedNotes)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .background(Color.gray.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                if let notes = device.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.body)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No notes")
                        .foregroundStyle(.tertiary)
                        .italic()
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    // MARK: - Actions Section

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Actions", systemImage: "bolt")
                .font(.headline)

            Divider()

            HStack(spacing: 12) {
                actionButton(title: "Ping", icon: "waveform.path") {
                    showPingSheet = true
                }

                actionButton(title: "Port Scan", icon: "network") {
                    showPortScanSheet = true
                }

                actionButton(title: "Copy IP", icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.ipAddress, forType: .string)
                }

                actionButton(title: "Copy MAC", icon: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(device.macAddress, forType: .string)
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
    }

    private func actionButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.title3)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Helpers

    private func latencyText(_ latency: Double) -> String {
        if latency < 1 { return "<1 ms" }
        return String(format: "%.0f ms", latency)
    }

    private var timeSinceLastSeen: String {
        let interval = Date().timeIntervalSince(device.lastSeen)
        if interval < 60 { return "Just now" }
        if interval < 3600 { return "\(Int(interval / 60)) min" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours" }
        return "\(Int(interval / 86400)) days"
    }

    private var totalTimeTracked: String {
        let interval = Date().timeIntervalSince(device.firstSeen)
        if interval < 3600 { return "\(Int(interval / 60)) min" }
        if interval < 86400 { return "\(Int(interval / 3600)) hours" }
        return "\(Int(interval / 86400)) days"
    }

    private func startEditing() {
        editedName = device.customName ?? ""
        editedNotes = device.notes ?? ""
        selectedDeviceType = device.deviceType
    }

    private func saveChanges() {
        device.customName = editedName.isEmpty ? nil : editedName
        device.notes = editedNotes.isEmpty ? nil : editedNotes
        device.deviceType = selectedDeviceType
        try? modelContext.save()
    }

    private func loadData() async {
        // Load bonjour services from coordinator if available
    }
}

// MARK: - Flow Layout for Tags

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.positions[index].x,
                                       y: bounds.minY + result.positions[index].y),
                         proposal: .unspecified)
        }
    }

    struct FlowResult {
        var size: CGSize = .zero
        var positions: [CGPoint] = []

        init(in width: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var maxHeight: CGFloat = 0

            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                if x + size.width > width, x > 0 {
                    x = 0
                    y += maxHeight + spacing
                    maxHeight = 0
                }
                positions.append(CGPoint(x: x, y: y))
                maxHeight = max(maxHeight, size.height)
                x += size.width + spacing
            }

            self.size = CGSize(width: width, height: y + maxHeight)
        }
    }
}

#Preview {
    ProDeviceDetailView(device: LocalDevice(
        ipAddress: "192.168.1.1",
        macAddress: "AA:BB:CC:DD:EE:FF",
        hostname: "router.local",
        vendor: "Apple",
        deviceType: .router,
        status: .online,
        lastLatency: 2.5,
        isGateway: true,
        supportsWakeOnLan: true,
        openPorts: [22, 80, 443, 8080],
        discoveredServices: ["SSH", "HTTP", "HTTPS", "HTTP-ALT"]
    ))
}
```

- [ ] **Step 2: Run xcodegen**

```bash
xcodegen generate
```

- [ ] **Step 3: Build and verify**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

- [ ] **Step 4: Commit**

```bash
git add NetMonitor-macOS/Views/Devices/ProDeviceDetailView.swift NetMonitor-2.0.xcodeproj/project.pbxproj
git commit -m "feat(macOS): Add ProDeviceDetailView with enhanced device details

- New full-page detail view for Pro mode
- Network details, ports & services, latency stats
- Hardware info, WOL, timeline sections
- Editable notes and actions

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Final Integration Test

**Files:**
- Test: Full flow verification

- [ ] **Step 1: Build entire project**

```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | tail -20
```

Expected: BUILD SUCCEEDED

- [ ] **Step 2: Verify navigation works**

Manual testing:
1. Open Devices view
2. Toggle to Pro mode
3. Verify full-screen table (no split)
4. Click a device row
5. Verify navigation to ProDeviceDetailView
6. Verify back navigation works
7. Toggle to Consumer mode
8. Verify split view still works

- [ ] **Step 3: Commit**

```bash
git commit --allow-empty -m "build: Verify Phase 2 Pro mode implementation

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Summary

After Phase 2:
- Pro mode: Full-screen table → click → full-page detail
- Consumer mode: Split view (unchanged)
- ProDeviceDetailView: Enhanced 9-section detail page
- All existing functionality preserved

---

## Spec Reference

See `docs/superpowers/specs/2026-03-06-devices-pro-mode-phase2-design.md` for full design.
