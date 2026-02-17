# NetMonitor macOS Phase 1: Foundation - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Establish the Xcode workspace, SwiftData models, and NavigationSplitView shell with Swift 6 strict concurrency enabled.

**Architecture:** Modern SwiftUI app with NavigationSplitView for macOS sidebar navigation, SwiftData for persistence, @Observable state management, and Swift 6 strict concurrency from day one.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, macOS 15.0+

**Reference Design:** `docs/plans/2026-01-10-netmonitor-macos-v1-design.md`

---

## Task 1: Create Xcode Project

**Files:**
- Create: `NetMonitor.xcodeproj` (via Xcode)
- Create: `NetMonitor/NetMonitorApp.swift`
- Create: `NetMonitor/ContentView.swift`

**Step 1: Create new Xcode project**

Actions:
1. Open Xcode
2. File → New → Project
3. Select macOS → App
4. Product Name: `NetMonitor`
5. Organization Identifier: `com.yourorg` (use your identifier)
6. Interface: SwiftUI
7. Language: Swift
8. Storage: None (we'll add SwiftData manually)
9. Include Tests: YES
10. Create Git repository: NO (already initialized)
11. Save to: `/Users/blake/Projects/NetMonitor/`

Expected: Xcode creates `NetMonitor.xcodeproj` and default files

**Step 2: Enable Swift 6 strict concurrency**

Actions:
1. Select NetMonitor project in navigator
2. Select NetMonitor target
3. Build Settings → Swift Compiler - Language
4. Set "Swift Language Version" to "Swift 6"
5. Build Settings → search "strict concurrency"
6. Set "Strict Concurrency Checking" to "Complete"

Expected: Swift 6 mode enabled, concurrency warnings become errors

**Step 3: Set minimum deployment target**

Actions:
1. Select NetMonitor target
2. General tab → Deployment Info
3. Set "Minimum Deployments" to "macOS 15.0"

Expected: Deployment target set to macOS 15.0+

**Step 4: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds with default template

**Step 5: Commit**

```bash
git add .
git commit -m "feat: create Xcode project with Swift 6 strict concurrency

- macOS 15.0+ target
- Swift 6 language mode
- Strict concurrency enabled

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Create NetMonitorShared Package

**Files:**
- Create: `NetMonitorShared/Package.swift`
- Create: `NetMonitorShared/Sources/NetMonitorShared/Common/Enums.swift`

**Step 1: Create Swift package**

Actions:
1. In Terminal, navigate to project root
2. Create package directory: `mkdir -p NetMonitorShared/Sources/NetMonitorShared/Common`
3. Create Package.swift

```bash
cd /Users/blake/Projects/NetMonitor
mkdir -p NetMonitorShared/Sources/NetMonitorShared/{Common,Communication}
mkdir -p NetMonitorShared/Tests/NetMonitorSharedTests
```

**Step 2: Write Package.swift**

Create: `NetMonitorShared/Package.swift`

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetMonitorShared",
    platforms: [
        .macOS(.v15),
        .iOS(.v18)
    ],
    products: [
        .library(
            name: "NetMonitorShared",
            targets: ["NetMonitorShared"]
        )
    ],
    targets: [
        .target(
            name: "NetMonitorShared",
            swiftSettings: [
                .enableUpcomingFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "NetMonitorSharedTests",
            dependencies: ["NetMonitorShared"]
        )
    ]
)
```

**Step 3: Create shared enums**

Create: `NetMonitorShared/Sources/NetMonitorShared/Common/Enums.swift`

```swift
import Foundation

/// Network connection type
public enum ConnectionType: String, Codable, Sendable, CaseIterable {
    case wifi = "WiFi"
    case ethernet = "Ethernet"
    case cellular = "Cellular"
    case unknown = "Unknown"
}

/// Monitoring protocol type
public enum TargetProtocol: String, Codable, Sendable, CaseIterable {
    case icmp = "ICMP"
    case http = "HTTP"
    case https = "HTTPS"
    case tcp = "TCP"
}

/// Local device type
public enum DeviceType: String, Codable, Sendable, CaseIterable {
    case phone = "Phone"
    case laptop = "Laptop"
    case tablet = "Tablet"
    case tv = "TV"
    case speaker = "Speaker"
    case gaming = "Gaming"
    case iot = "IoT"
    case router = "Router"
    case printer = "Printer"
    case unknown = "Unknown"

    public var iconName: String {
        switch self {
        case .phone: return "iphone"
        case .laptop: return "laptopcomputer"
        case .tablet: return "ipad"
        case .tv: return "tv"
        case .speaker: return "homepod"
        case .gaming: return "gamecontroller"
        case .iot: return "sensor"
        case .router: return "wifi.router"
        case .printer: return "printer"
        case .unknown: return "questionmark.circle"
        }
    }
}
```

**Step 4: Add package to Xcode project**

Actions:
1. In Xcode, File → Add Package Dependencies
2. Click "Add Local..."
3. Navigate to `NetMonitorShared` folder
4. Click "Add Package"
5. Select NetMonitor target
6. Add "NetMonitorShared" library
7. Click "Add Package"

Expected: NetMonitorShared appears in project navigator under "Package Dependencies"

**Step 5: Verify package builds**

Run: `⌘+B` (Build)

Expected: Build succeeds, no errors

**Step 6: Commit**

```bash
git add NetMonitorShared/
git commit -m "feat: add NetMonitorShared package with common enums

- Swift 6 strict concurrency enabled
- Shared enums: ConnectionType, TargetProtocol, DeviceType
- Platform support: macOS 15+, iOS 18+

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Add SwiftData Models

**Files:**
- Create: `NetMonitor/Models/NetworkTarget.swift`
- Create: `NetMonitor/Models/TargetMeasurement.swift`
- Create: `NetMonitor/Models/LocalDevice.swift`
- Create: `NetMonitor/Models/MonitoringSession.swift`

**Step 1: Create Models folder**

Actions:
1. In Xcode, right-click NetMonitor folder
2. New Group → "Models"

**Step 2: Create NetworkTarget model**

Create: `NetMonitor/Models/NetworkTarget.swift`

```swift
import Foundation
import SwiftData
import NetMonitorShared

@Model
final class NetworkTarget {
    var id: UUID
    var name: String
    var host: String
    var port: Int?
    var targetProtocol: TargetProtocol
    var checkInterval: TimeInterval
    var timeout: TimeInterval
    var isEnabled: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TargetMeasurement.target)
    var measurements: [TargetMeasurement] = []

    init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: Int? = nil,
        targetProtocol: TargetProtocol,
        checkInterval: TimeInterval = 5.0,
        timeout: TimeInterval = 3.0,
        isEnabled: Bool = true,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.targetProtocol = targetProtocol
        self.checkInterval = checkInterval
        self.timeout = timeout
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }
}
```

**Step 3: Create TargetMeasurement model**

Create: `NetMonitor/Models/TargetMeasurement.swift`

```swift
import Foundation
import SwiftData

@Model
final class TargetMeasurement {
    var id: UUID
    var timestamp: Date
    var latency: Double?
    var isReachable: Bool
    var errorMessage: String?

    var target: NetworkTarget?

    init(
        id: UUID = UUID(),
        timestamp: Date = .now,
        latency: Double? = nil,
        isReachable: Bool,
        errorMessage: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.latency = latency
        self.isReachable = isReachable
        self.errorMessage = errorMessage
    }
}
```

**Step 4: Create LocalDevice model**

Create: `NetMonitor/Models/LocalDevice.swift`

```swift
import Foundation
import SwiftData
import NetMonitorShared

@Model
final class LocalDevice {
    var id: UUID
    var ipAddress: String
    var macAddress: String
    var hostname: String?
    var vendor: String?
    var deviceType: DeviceType
    var customName: String?
    var notes: String?
    var firstSeen: Date
    var lastSeen: Date
    var isOnline: Bool

    init(
        id: UUID = UUID(),
        ipAddress: String,
        macAddress: String,
        hostname: String? = nil,
        vendor: String? = nil,
        deviceType: DeviceType = .unknown,
        customName: String? = nil,
        notes: String? = nil,
        firstSeen: Date = .now,
        lastSeen: Date = .now,
        isOnline: Bool = true
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendor = vendor
        self.deviceType = deviceType
        self.customName = customName
        self.notes = notes
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.isOnline = isOnline
    }
}
```

**Step 5: Create MonitoringSession model**

Create: `NetMonitor/Models/MonitoringSession.swift`

```swift
import Foundation
import SwiftData

@Model
final class MonitoringSession {
    var id: UUID
    var startedAt: Date
    var pausedAt: Date?
    var stoppedAt: Date?
    var isActive: Bool

    init(
        id: UUID = UUID(),
        startedAt: Date = .now,
        pausedAt: Date? = nil,
        stoppedAt: Date? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.startedAt = startedAt
        self.pausedAt = pausedAt
        self.stoppedAt = stoppedAt
        self.isActive = isActive
    }
}
```

**Step 6: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds, all models compile

**Step 7: Commit**

```bash
git add NetMonitor/Models/
git commit -m "feat: add SwiftData models for monitoring

- NetworkTarget with measurements relationship
- TargetMeasurement with latency and reachability
- LocalDevice with network discovery data
- MonitoringSession for session tracking

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Set Up SwiftData Container in App

**Files:**
- Modify: `NetMonitor/NetMonitorApp.swift`

**Step 1: Update NetMonitorApp with SwiftData**

Modify: `NetMonitor/NetMonitorApp.swift`

Replace entire file with:

```swift
import SwiftUI
import SwiftData

@main
struct NetMonitorApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            NetworkTarget.self,
            TargetMeasurement.self,
            LocalDevice.self,
            MonitoringSession.self
        ])

        Settings {
            SettingsView()
        }
    }
}
```

**Step 2: Create placeholder SettingsView**

Create: `NetMonitor/Views/SettingsView.swift`

First create Views folder:
1. Right-click NetMonitor folder
2. New Group → "Views"

Then create file:

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View {
        Text("Settings")
            .frame(width: 400, height: 300)
    }
}

#Preview {
    SettingsView()
}
```

**Step 3: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 4: Run app**

Run: `⌘+R` (Run)

Expected: App launches showing "Hello, world!" (default ContentView)

**Step 5: Commit**

```bash
git add NetMonitor/NetMonitorApp.swift NetMonitor/Views/
git commit -m "feat: configure SwiftData container in app

- ModelContainer for all data models
- Settings scene placeholder

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Create NavigationSplitView Shell

**Files:**
- Modify: `NetMonitor/ContentView.swift`
- Create: `NetMonitor/Views/SidebarView.swift`
- Create: `NetMonitor/Views/DashboardView.swift`

**Step 1: Create Section enum**

Create: `NetMonitor/Models/Section.swift`

```swift
import Foundation

enum Section: String, CaseIterable, Identifiable {
    case dashboard = "Dashboard"
    case targets = "Targets"
    case devices = "Devices"
    case tools = "Tools"
    case settings = "Settings"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .dashboard: return "chart.line.uptrend.xyaxis"
        case .targets: return "target"
        case .devices: return "network"
        case .tools: return "wrench.and.screwdriver"
        case .settings: return "gearshape"
        }
    }
}
```

**Step 2: Create SidebarView**

Create: `NetMonitor/Views/SidebarView.swift`

```swift
import SwiftUI

struct SidebarView: View {
    @Binding var selection: Section?

    var body: some View {
        List(Section.allCases, selection: $selection) { section in
            Label(section.rawValue, systemImage: section.iconName)
                .tag(section)
        }
        .navigationTitle("NetMonitor")
        .frame(minWidth: 220)
    }
}

#Preview {
    @Previewable @State var selection: Section? = .dashboard

    SidebarView(selection: $selection)
}
```

**Step 3: Create DashboardView placeholder**

Create: `NetMonitor/Views/DashboardView.swift`

```swift
import SwiftUI

struct DashboardView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Session monitoring will appear here")
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Dashboard")
    }
}

#Preview {
    DashboardView()
}
```

**Step 4: Create placeholder views for other sections**

Create: `NetMonitor/Views/TargetsView.swift`

```swift
import SwiftUI

struct TargetsView: View {
    var body: some View {
        Text("Targets")
            .navigationTitle("Targets")
    }
}

#Preview {
    TargetsView()
}
```

Create: `NetMonitor/Views/DevicesView.swift`

```swift
import SwiftUI

struct DevicesView: View {
    var body: some View {
        Text("Devices")
            .navigationTitle("Devices")
    }
}

#Preview {
    DevicesView()
}
```

Create: `NetMonitor/Views/ToolsView.swift`

```swift
import SwiftUI

struct ToolsView: View {
    var body: some View {
        Text("Tools")
            .navigationTitle("Tools")
    }
}

#Preview {
    ToolsView()
}
```

**Step 5: Update ContentView with NavigationSplitView**

Modify: `NetMonitor/ContentView.swift`

Replace entire file with:

```swift
import SwiftUI

struct ContentView: View {
    @State private var selectedSection: Section? = .dashboard

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selectedSection)
        } detail: {
            switch selectedSection {
            case .dashboard:
                DashboardView()
            case .targets:
                TargetsView()
            case .devices:
                DevicesView()
            case .tools:
                ToolsView()
            case .settings:
                SettingsView()
            case nil:
                Text("Select a section")
            }
        }
        .frame(minWidth: 900, minHeight: 600)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [
            NetworkTarget.self,
            TargetMeasurement.self,
            LocalDevice.self,
            MonitoringSession.self
        ], inMemory: true)
}
```

**Step 6: Run app to verify navigation**

Run: `⌘+R` (Run)

Expected:
- App shows sidebar with 5 sections
- Clicking each section shows corresponding view
- Window has minimum size 900x600

**Step 7: Commit**

```bash
git add NetMonitor/Views/ NetMonitor/Models/Section.swift NetMonitor/ContentView.swift
git commit -m "feat: implement NavigationSplitView shell with sidebar

- Sidebar with Dashboard, Targets, Devices, Tools, Settings
- Section enum with icons
- Placeholder views for all sections
- Minimum window size 900x600

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Add Preview Data Helper

**Files:**
- Create: `NetMonitor/Preview Content/PreviewContainer.swift`

**Step 1: Create preview container helper**

Create: `NetMonitor/Preview Content/PreviewContainer.swift`

```swift
import SwiftData

/// Helper for creating in-memory ModelContainer for SwiftUI previews
@MainActor
struct PreviewContainer {
    let container: ModelContainer

    init() {
        do {
            let schema = Schema([
                NetworkTarget.self,
                TargetMeasurement.self,
                LocalDevice.self,
                MonitoringSession.self
            ])

            let configuration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true
            )

            container = try ModelContainer(
                for: schema,
                configurations: [configuration]
            )

            // Add sample data for previews
            addSampleData()
        } catch {
            fatalError("Failed to create preview container: \(error)")
        }
    }

    private func addSampleData() {
        let context = container.mainContext

        // Sample targets
        let cloudflare = NetworkTarget(
            name: "Cloudflare DNS",
            host: "1.1.1.1",
            targetProtocol: .icmp
        )

        let google = NetworkTarget(
            name: "Google DNS",
            host: "8.8.8.8",
            targetProtocol: .icmp
        )

        context.insert(cloudflare)
        context.insert(google)

        // Sample device
        let device = LocalDevice(
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "iPhone",
            deviceType: .phone
        )

        context.insert(device)
    }
}
```

**Step 2: Update preview in ContentView**

Modify: `NetMonitor/ContentView.swift`

Update the #Preview section:

```swift
#Preview {
    ContentView()
        .modelContainer(PreviewContainer().container)
}
```

**Step 3: Run preview**

Actions:
1. Open ContentView.swift
2. Click "Resume" in preview canvas (or ⌥⌘P)

Expected: Preview shows app with sidebar navigation

**Step 4: Commit**

```bash
git add "NetMonitor/Preview Content/PreviewContainer.swift" NetMonitor/ContentView.swift
git commit -m "feat: add preview container helper with sample data

- In-memory container for SwiftUI previews
- Sample targets and devices
- Prevents preview data pollution

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 7: Add Accessibility Identifiers

**Files:**
- Modify: `NetMonitor/Views/SidebarView.swift`

**Step 1: Add accessibility identifiers to sidebar**

Modify: `NetMonitor/Views/SidebarView.swift`

Update the List:

```swift
List(Section.allCases, selection: $selection) { section in
    Label(section.rawValue, systemImage: section.iconName)
        .tag(section)
        .accessibilityIdentifier("sidebar_\(section.rawValue.lowercased())")
}
.navigationTitle("NetMonitor")
.frame(minWidth: 220)
.accessibilityIdentifier("sidebar_navigation")
```

**Step 2: Add identifiers to ContentView**

Modify: `NetMonitor/ContentView.swift`

Update NavigationSplitView:

```swift
NavigationSplitView {
    SidebarView(selection: $selectedSection)
} detail: {
    switch selectedSection {
    case .dashboard:
        DashboardView()
            .accessibilityIdentifier("detail_dashboard")
    case .targets:
        TargetsView()
            .accessibilityIdentifier("detail_targets")
    case .devices:
        DevicesView()
            .accessibilityIdentifier("detail_devices")
    case .tools:
        ToolsView()
            .accessibilityIdentifier("detail_tools")
    case .settings:
        SettingsView()
            .accessibilityIdentifier("detail_settings")
    case nil:
        Text("Select a section")
            .accessibilityIdentifier("detail_empty")
    }
}
.frame(minWidth: 900, minHeight: 600)
```

**Step 3: Verify build**

Run: `⌘+B` (Build)

Expected: Build succeeds

**Step 4: Commit**

```bash
git add NetMonitor/Views/
git commit -m "feat: add accessibility identifiers to navigation

- Sidebar navigation items
- Detail view containers
- Enables UI automation and accessibility

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Task 8: Update CLAUDE.md with Build Commands

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add build commands**

Modify: `CLAUDE.md`

Update the "Development Commands" section:

```markdown
## Development Commands

### Building
```bash
# Build the project
xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor -configuration Debug build

# Clean build folder
xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor clean
```

### Running
```bash
# Run from command line
xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor -configuration Debug

# Or use Xcode: ⌘+R
```

### Testing
```bash
# Run all tests
xcodebuild -project NetMonitor.xcodeproj -scheme NetMonitor test

# Or use Xcode: ⌘+U
```

### Code Quality
- Swift 6 strict concurrency mode enabled
- Build warnings treated as errors for concurrency issues
- Use Xcode's "Strict Concurrency Checking" in build settings
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add build and test commands to CLAUDE.md

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

---

## Phase 1 Complete - Verification Checklist

Before moving to Phase 2, verify:

- [ ] App builds without errors (`⌘+B`)
- [ ] App runs and shows NavigationSplitView (`⌘+R`)
- [ ] Sidebar navigation works (click each section)
- [ ] Swift 6 strict concurrency enabled (check build settings)
- [ ] SwiftData container configured
- [ ] All 4 models created (NetworkTarget, TargetMeasurement, LocalDevice, MonitoringSession)
- [ ] NetMonitorShared package linked and builds
- [ ] Preview works with sample data
- [ ] Accessibility identifiers on navigation elements
- [ ] All changes committed to git

---

## Next Steps

**Phase 1 Foundation is now complete.** The next implementation plan will be:

**Phase 2: Core Monitoring Engine**
- File: `docs/plans/2026-01-10-netmonitor-macos-phase2-monitoring.md`
- Features: MonitoringSession with AsyncStream, ICMPMonitorService, HTTPMonitorService, basic Dashboard with live results

**To proceed with Phase 2 implementation, create the Phase 2 plan following the same structure.**
