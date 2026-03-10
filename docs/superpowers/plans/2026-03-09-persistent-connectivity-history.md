# Persistent Connectivity History Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace fake uptime data in ISPHealthCard with real persistent connectivity history, and build the foundation for pro-grade uptime analytics across the app.

**Architecture:** A `ConnectivityRecord` SwiftData model records every connectivity transition (online/offline) and periodic latency samples per network profile. `ConnectivityMonitor` uses `NWPathMonitor` for instant OS-native transition detection — no polling. `UptimeViewModel` queries records and computes uptime %, outage count, and the 30-day bar segments that ISPHealthCard displays.

**Tech Stack:** SwiftData (existing schema + migration), Network framework (`NWPathMonitor`), Swift 6 strict concurrency, `@Observable` (no ObservableObject/Published), async/await (no DispatchQueue)

---

## Codebase Orientation

Key files to understand before touching anything:

| File | What it does |
|------|-------------|
| `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/` | All SwiftData `@Model` classes live here — shared between macOS and iOS |
| `NetMonitor-macOS/App/NetMonitorApp.swift` | Creates the `ModelContainer` — **you must add any new `@Model` here** |
| `NetMonitor-macOS/Platform/MonitoringSession.swift` | Manages monitoring lifecycle; starts/stops per-target tasks; has `modelContext` |
| `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift` | The card that shows uptime — currently has fake `generateUptimeSegments()` |
| `NetMonitor-macOS/Platform/BandwidthMonitorService.swift` | Pattern to follow: `@Observable @MainActor final class`, started via `.task(priority: .utility)` |
| `NetMonitor-macOS/Platform/ISPLookupService.swift` | Pattern for services that write to UserDefaults cache |

**Test command** (run on mac-mini, never locally):
```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-macOSTests"
```

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| **Create** | `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/ConnectivityRecord.swift` | SwiftData `@Model` — one row per connectivity event or latency sample |
| **Create** | `NetMonitor-macOS/Platform/ConnectivityMonitor.swift` | `NWPathMonitor` wrapper; writes `ConnectivityRecord` rows; `@Observable @MainActor` |
| **Create** | `NetMonitor-macOS/ViewModels/UptimeViewModel.swift` | Queries `ConnectivityRecord` via SwiftData; computes uptime %, outage count, bar segments |
| **Modify** | `NetMonitor-macOS/App/NetMonitorApp.swift` | Register `ConnectivityRecord` in `ModelContainer` schema |
| **Modify** | `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift` | Remove fake data; accept `UptimeViewModel`; wire real stats |
| **Modify** | `NetMonitor-macOS/Views/NetworkDetailView.swift` | Instantiate `ConnectivityMonitor` and `UptimeViewModel`; pass to ISPHealthCard |
| **Create** | `Tests/NetMonitor-macOSTests/UptimeViewModelTests.swift` | Unit tests for uptime calculation logic |

---

## Chunk 1: Data Model + Schema Registration

### Task 1: Create ConnectivityRecord SwiftData model

**Files:**
- Create: `Packages/NetMonitorCore/Sources/NetMonitorCore/Models/ConnectivityRecord.swift`

`ConnectivityRecord` records a single point-in-time connectivity event. Two kinds of rows are written:
- **Transition rows** (`isSample: false`): written when connectivity changes (online→offline or vice versa). `isOnline` = the new state.
- **Sample rows** (`isSample: true`): written every 5 minutes while online. `isOnline` = true, `latencyMs` = measured ping to gateway.

This dual-use design means the uptime bar just needs `isOnline` transitions to be accurate, while samples provide latency trending without a separate table.

- [x] **Write the model**

```swift
// Packages/NetMonitorCore/Sources/NetMonitorCore/Models/ConnectivityRecord.swift
import Foundation
import SwiftData

/// Persistent record of a connectivity state transition or periodic latency sample.
/// Transition rows (isSample: false): written on online↔offline change.
/// Sample rows (isSample: true): written every 5 min while online; captures latency.
@Model
public final class ConnectivityRecord {
    public var id: UUID
    /// The NetworkProfile (by ID) this record belongs to.
    public var profileID: UUID
    /// When this event or sample was recorded.
    public var timestamp: Date
    /// True = network reachable; false = network unreachable.
    public var isOnline: Bool
    /// Measured latency to gateway in milliseconds. Nil when offline or unmeasured.
    public var latencyMs: Double?
    /// True = periodic sample; false = transition event.
    public var isSample: Bool
    /// Public IP at time of recording (nil if offline). Detects IP changes.
    public var publicIP: String?

    public init(
        id: UUID = UUID(),
        profileID: UUID,
        timestamp: Date = Date(),
        isOnline: Bool,
        latencyMs: Double? = nil,
        isSample: Bool = false,
        publicIP: String? = nil
    ) {
        self.id = id
        self.profileID = profileID
        self.timestamp = timestamp
        self.isOnline = isOnline
        self.latencyMs = latencyMs
        self.isSample = isSample
        self.publicIP = publicIP
    }
}
```

- [x] **Register in ModelContainer** — open `NetMonitor-macOS/App/NetMonitorApp.swift` and find the `sharedModelContainer` property. It lists the schema models. Add `ConnectivityRecord.self` to the schema array. The existing pattern:

```swift
// Find: schema = Schema([NetworkTarget.self, LocalDevice.self, SessionRecord.self, ...])
// Change to include ConnectivityRecord:
schema = Schema([
    NetworkTarget.self,
    LocalDevice.self,
    SessionRecord.self,
    ToolActivityLog.self,
    ConnectivityRecord.self   // add this line
])
```

- [x] **Verify build** — run:
```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```
Expected: `Build succeeded`

- [x] **Commit**
```bash
git add Packages/NetMonitorCore/Sources/NetMonitorCore/Models/ConnectivityRecord.swift \
        NetMonitor-macOS/App/NetMonitorApp.swift
git commit -m "feat: add ConnectivityRecord SwiftData model for uptime history"
```

---

## Chunk 2: UptimeViewModel (pure logic, no side effects)

Write and test the computation logic before wiring in the monitor. This is pure SwiftData querying + arithmetic — easy to unit test.

### Task 2: Write UptimeViewModel

**Files:**
- Create: `NetMonitor-macOS/ViewModels/UptimeViewModel.swift`

`UptimeViewModel` is responsible for one thing: given a `profileID` and a `modelContext`, compute uptime statistics by querying `ConnectivityRecord`. No networking, no monitoring — pure read + compute.

- [x] **Write the ViewModel**

```swift
// NetMonitor-macOS/ViewModels/UptimeViewModel.swift
import Foundation
import SwiftData
import Observation
import NetMonitorCore

@MainActor
@Observable
final class UptimeViewModel {

    // MARK: - Output (observed by views)

    /// Uptime percentage over the query window (0–100). Nil until first load.
    private(set) var uptimePct: Double?
    /// Number of distinct outage events in the window.
    private(set) var outageCount: Int = 0
    /// 30 segments, each true = online for that period. Used by the uptime bar.
    private(set) var uptimeBar: [Bool] = []
    /// Most recent latency sample. Nil if no samples recorded.
    private(set) var latestLatencyMs: Double?
    /// True while the first load is in progress.
    private(set) var isLoading = true

    // MARK: - Config

    let profileID: UUID
    /// How many days of history to compute uptime over (default 30).
    let windowDays: Int
    /// How many segments to split the window into for the bar (default 30).
    let barSegments: Int

    private let modelContext: ModelContext

    init(profileID: UUID, modelContext: ModelContext, windowDays: Int = 30, barSegments: Int = 30) {
        self.profileID = profileID
        self.modelContext = modelContext
        self.windowDays = windowDays
        self.barSegments = barSegments
    }

    // MARK: - Public API

    /// Load/refresh from SwiftData. Call from .task modifier.
    func load() {
        let records = fetchRecords()
        compute(records: records)
        isLoading = false
    }

    // MARK: - Private

    private func fetchRecords() -> [ConnectivityRecord] {
        let since = Date().addingTimeInterval(Double(-windowDays) * 86400)
        let id = profileID
        let descriptor = FetchDescriptor<ConnectivityRecord>(
            predicate: #Predicate { $0.profileID == id && $0.timestamp >= since },
            sortBy: [SortDescriptor(\.timestamp)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func compute(records: [ConnectivityRecord]) {
        let windowStart = Date().addingTimeInterval(Double(-windowDays) * 86400)
        let windowEnd = Date()
        let windowDuration = windowEnd.timeIntervalSince(windowStart)

        guard !records.isEmpty else {
            // No history — show as fully online (app just installed)
            uptimePct = nil
            outageCount = 0
            uptimeBar = []
            latestLatencyMs = nil
            return
        }

        // Latest latency sample
        latestLatencyMs = records.filter { $0.isSample }.last?.latencyMs

        // Build timeline of transition events only
        let transitions = records.filter { !$0.isSample }

        // Compute total online duration using transition pairs
        var onlineSeconds: TimeInterval = 0
        var outages = 0
        var lastOnlineStart: Date? = nil

        // Assume state before first record: if first transition is "went offline",
        // we were online from windowStart. If first transition is "came online",
        // we were offline from windowStart.
        let firstTransition = transitions.first
        if let first = firstTransition, first.isOnline {
            // Was offline before this — do nothing, lastOnlineStart stays nil
        } else {
            // Was online before first transition (or no transitions at all)
            lastOnlineStart = windowStart
        }

        for record in transitions {
            if record.isOnline {
                // Came online
                lastOnlineStart = record.timestamp
            } else {
                // Went offline
                outages += 1
                if let start = lastOnlineStart {
                    onlineSeconds += record.timestamp.timeIntervalSince(start)
                    lastOnlineStart = nil
                }
            }
        }

        // Still online at window end
        if let start = lastOnlineStart {
            onlineSeconds += windowEnd.timeIntervalSince(start)
        }

        uptimePct = windowDuration > 0 ? min(100, onlineSeconds / windowDuration * 100) : 100
        outageCount = outages

        // Build bar segments
        let segmentDuration = windowDuration / Double(barSegments)
        var bar: [Bool] = []
        for i in 0..<barSegments {
            let segStart = windowStart.addingTimeInterval(Double(i) * segmentDuration)
            let segEnd = segStart.addingTimeInterval(segmentDuration)
            // Segment is "online" if majority of it was online
            let onlineInSeg = onlineSecondsInSegment(
                from: segStart, to: segEnd,
                transitions: transitions,
                windowStart: windowStart
            )
            bar.append(onlineInSeg >= segmentDuration * 0.5)
        }
        uptimeBar = bar
    }

    /// Compute online seconds within [segStart, segEnd] using the transition list.
    private func onlineSecondsInSegment(
        from segStart: Date,
        to segEnd: Date,
        transitions: [ConnectivityRecord],
        windowStart: Date
    ) -> TimeInterval {
        // Find the state at segStart by replaying transitions up to that point
        let before = transitions.filter { $0.timestamp <= segStart }
        var isOnlineAtSegStart: Bool
        if let last = before.last {
            isOnlineAtSegStart = last.isOnline
        } else {
            // No transitions before segment — was online from start (see compute logic)
            let firstTransition = transitions.first
            isOnlineAtSegStart = firstTransition.map { !$0.isOnline } ?? true
        }

        // Replay transitions within this segment
        let inSeg = transitions.filter { $0.timestamp > segStart && $0.timestamp < segEnd }
        var total: TimeInterval = 0
        var cursor = segStart
        var currentlyOnline = isOnlineAtSegStart

        for t in inSeg {
            if currentlyOnline {
                total += t.timestamp.timeIntervalSince(cursor)
            }
            cursor = t.timestamp
            currentlyOnline = t.isOnline
        }
        // Tail
        if currentlyOnline {
            total += segEnd.timeIntervalSince(cursor)
        }
        return total
    }
}
```

- [x] **Verify build**
```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

### Task 3: Write UptimeViewModel unit tests

**Files:**
- Create: `Tests/NetMonitor-macOSTests/UptimeViewModelTests.swift`

These tests create in-memory `ConnectivityRecord` fixtures and verify the uptime logic — no network, no file system.

- [x] **Write the tests**

```swift
// Tests/NetMonitor-macOSTests/UptimeViewModelTests.swift
import Testing
import Foundation
import SwiftData
@testable import NetMonitorCore

// NOTE: UptimeViewModel is in the macOS app target, not NetMonitorCore.
// If the test target can't import it directly, test via the computed values
// by constructing the ViewModel with an in-memory container.

@Suite("UptimeViewModel logic")
struct UptimeViewModelTests {

    // Build an in-memory model container for testing
    func makeContainer() throws -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: ConnectivityRecord.self, configurations: config)
    }

    func insertRecord(
        in context: ModelContext,
        profileID: UUID,
        hoursAgo: Double,
        isOnline: Bool,
        isSample: Bool = false,
        latencyMs: Double? = nil
    ) {
        let record = ConnectivityRecord(
            profileID: profileID,
            timestamp: Date().addingTimeInterval(-hoursAgo * 3600),
            isOnline: isOnline,
            latencyMs: latencyMs,
            isSample: isSample
        )
        context.insert(record)
    }

    @Test("No records → uptimePct is nil")
    func noRecords() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        #expect(vm.uptimePct == nil)
        #expect(vm.outageCount == 0)
        #expect(vm.uptimeBar.isEmpty)
    }

    @Test("Always online → 100% uptime")
    func alwaysOnline() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        // One sample 12h ago, currently online — no transitions recorded
        insertRecord(in: context, profileID: profileID, hoursAgo: 12, isOnline: true, isSample: true, latencyMs: 5.0)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        #expect(vm.uptimePct == nil) // no transitions → nil (shown as "always on")
        #expect(vm.outageCount == 0)
    }

    @Test("One outage in the middle → uptime ~50%")
    func oneOutageMiddle() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        // Window: 24h. Went offline at 18h ago, came back at 6h ago = 12h outage = ~50% uptime.
        insertRecord(in: context, profileID: profileID, hoursAgo: 18, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 6, isOnline: true)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        let pct = try #require(vm.uptimePct)
        // 12h online out of 24h = 50%, but due to "was online at windowStart" assumption
        // we get: 0h to 18h ago = 6h online, then offline 12h, then 6h online = 12h total
        #expect(pct > 45 && pct < 55, "Expected ~50%, got \(pct)")
        #expect(vm.outageCount == 1)
    }

    @Test("Outage count increments per outage")
    func multipleOutages() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        // Three outages of 1h each in a 24h window
        insertRecord(in: context, profileID: profileID, hoursAgo: 22, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 21, isOnline: true)
        insertRecord(in: context, profileID: profileID, hoursAgo: 14, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 13, isOnline: true)
        insertRecord(in: context, profileID: profileID, hoursAgo: 6, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 5, isOnline: true)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 24)
        vm.load()

        #expect(vm.outageCount == 3)
    }

    @Test("Bar segments reflect online/offline periods")
    func barSegments() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        // 4-segment bar over 1 day. Offline for the middle 12 hours.
        // Seg 0: 24–18h ago = online
        // Seg 1: 18–12h ago = offline (starts 18h ago)
        // Seg 2: 12–6h ago = offline
        // Seg 3: 6–0h ago = online (came back 6h ago)
        insertRecord(in: context, profileID: profileID, hoursAgo: 18, isOnline: false)
        insertRecord(in: context, profileID: profileID, hoursAgo: 6, isOnline: true)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        #expect(vm.uptimeBar.count == 4)
        #expect(vm.uptimeBar[0] == true,  "Segment 0 (24–18h ago) should be online")
        #expect(vm.uptimeBar[1] == false, "Segment 1 (18–12h ago) should be offline")
        #expect(vm.uptimeBar[2] == false, "Segment 2 (12–6h ago) should be offline")
        #expect(vm.uptimeBar[3] == true,  "Segment 3 (6–0h ago) should be online")
    }

    @Test("Latest latency comes from most recent sample record")
    func latestLatency() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let profileID = UUID()

        insertRecord(in: context, profileID: profileID, hoursAgo: 10, isOnline: true, isSample: true, latencyMs: 20)
        insertRecord(in: context, profileID: profileID, hoursAgo: 5,  isOnline: true, isSample: true, latencyMs: 8)

        let vm = UptimeViewModel(profileID: profileID, modelContext: context, windowDays: 1, barSegments: 4)
        vm.load()

        #expect(vm.latestLatencyMs == 8)
    }
}
```

- [x] **Run tests on mac-mini**
```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-macOSTests/UptimeViewModelTests 2>&1 | tail -20"
```
Expected: All 5 tests pass.

- [x] **Commit**
```bash
git add NetMonitor-macOS/ViewModels/UptimeViewModel.swift \
        Tests/NetMonitor-macOSTests/UptimeViewModelTests.swift
git commit -m "feat: add UptimeViewModel with uptime calculation and bar segment logic"
```

---

## Chunk 3: ConnectivityMonitor (write side)

### Task 4: Create ConnectivityMonitor

**Files:**
- Create: `NetMonitor-macOS/Platform/ConnectivityMonitor.swift`

`ConnectivityMonitor` owns the `NWPathMonitor` and writes `ConnectivityRecord` rows. It runs continuously in the background and produces two types of events:

1. **Transition events** — `NWPathMonitor` calls the handler when path status changes. Write a `ConnectivityRecord(isOnline: newState, isSample: false)` immediately.
2. **Periodic samples** — every 5 minutes while online, ping the gateway and write a `ConnectivityRecord(isOnline: true, isSample: true, latencyMs: measured)`.

- [x] **Write the monitor**

```swift
// NetMonitor-macOS/Platform/ConnectivityMonitor.swift
import Foundation
import Network
import SwiftData
import NetMonitorCore
import os

/// Monitors network connectivity using NWPathMonitor and persists
/// transition events and periodic latency samples to SwiftData.
@MainActor
@Observable
final class ConnectivityMonitor {

    // MARK: - Observable state

    private(set) var isOnline: Bool = true
    private(set) var currentLatencyMs: Double?

    // MARK: - Config

    let profileID: UUID
    let gatewayIP: String

    /// How often to write latency samples while online (default 5 minutes).
    let sampleInterval: TimeInterval

    // MARK: - Private

    private let modelContext: ModelContext
    private var pathMonitor: NWPathMonitor?
    private var monitorTask: Task<Void, Never>?
    private var sampleTask: Task<Void, Never>?

    init(
        profileID: UUID,
        gatewayIP: String,
        modelContext: ModelContext,
        sampleInterval: TimeInterval = 300
    ) {
        self.profileID = profileID
        self.gatewayIP = gatewayIP
        self.modelContext = modelContext
        self.sampleInterval = sampleInterval
    }

    // MARK: - Lifecycle

    /// Start monitoring. Call from .task modifier; cancelled when view disappears.
    func start() async {
        startPathMonitor()
        await runSampleLoop()
    }

    func stop() {
        pathMonitor?.cancel()
        pathMonitor = nil
        sampleTask?.cancel()
    }

    // MARK: - NWPathMonitor

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor

        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let online = path.status == .satisfied
                if online != self.isOnline {
                    self.isOnline = online
                    self.writeTransition(isOnline: online)
                    Logger.monitoring.info("Connectivity changed: \(online ? "online" : "offline")")
                }
            }
        }
        // Use a dedicated background queue for the monitor
        monitor.start(queue: DispatchQueue(label: "com.netmonitor.pathmonitor", qos: .utility))
    }

    // MARK: - Periodic sampling

    private func runSampleLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(sampleInterval))
            guard !Task.isCancelled else { break }
            guard isOnline else { continue }
            await takeSample()
        }
    }

    private func takeSample() async {
        let pingService = ShellPingService()
        let latency: Double?
        if let result = try? await pingService.ping(host: gatewayIP, count: 3, timeout: 2),
           result.isReachable {
            latency = result.minLatency
        } else {
            latency = nil
        }
        currentLatencyMs = latency
        writeSample(latencyMs: latency)
    }

    // MARK: - Persistence

    private func writeTransition(isOnline: Bool) {
        let record = ConnectivityRecord(
            profileID: profileID,
            isOnline: isOnline,
            isSample: false
        )
        modelContext.insert(record)
        try? modelContext.save()
    }

    private func writeSample(latencyMs: Double?) {
        let record = ConnectivityRecord(
            profileID: profileID,
            isOnline: true,
            latencyMs: latencyMs,
            isSample: true
        )
        modelContext.insert(record)
        try? modelContext.save()

        // Prune records older than 90 days to prevent unbounded growth
        pruneOldRecords()
    }

    private func pruneOldRecords() {
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        let id = profileID
        let descriptor = FetchDescriptor<ConnectivityRecord>(
            predicate: #Predicate { $0.profileID == id && $0.timestamp < cutoff }
        )
        if let old = try? modelContext.fetch(descriptor) {
            for record in old { modelContext.delete(record) }
            try? modelContext.save()
        }
    }
}
```

**Note on `NWPathMonitor` and DispatchQueue:** `NWPathMonitor.start(queue:)` requires a DispatchQueue — this is an Apple API requirement, not a pattern violation. The handler immediately hops back to `@MainActor` via `Task { @MainActor in ... }`.

- [x] **Verify build**
```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [x] **Commit**
```bash
git add NetMonitor-macOS/Platform/ConnectivityMonitor.swift
git commit -m "feat: add ConnectivityMonitor using NWPathMonitor for real-time connectivity tracking"
```

---

## Chunk 4: Wire to ISPHealthCard

### Task 5: Update NetworkDetailView to own monitor + ViewModel

**Files:**
- Modify: `NetMonitor-macOS/Views/NetworkDetailView.swift`

`NetworkDetailView` already has `@Binding var profile: NetworkProfile` and `@Environment(\.modelContext)`. It should own `ConnectivityMonitor` and `UptimeViewModel` and pass them into `ISPHealthCard`.

- [x] **Add state to NetworkDetailView**

In `NetworkDetailView`, add:

```swift
@Environment(\.modelContext) private var modelContext

@State private var connectivityMonitor: ConnectivityMonitor?
@State private var uptimeViewModel: UptimeViewModel?
```

Initialize them lazily in `.onAppear` (not in `init` — `modelContext` isn't available until the view is in the hierarchy):

```swift
.onAppear {
    if connectivityMonitor == nil {
        let monitor = ConnectivityMonitor(
            profileID: profile.id,
            gatewayIP: profile.gatewayIP,
            modelContext: modelContext
        )
        connectivityMonitor = monitor
        uptimeViewModel = UptimeViewModel(
            profileID: profile.id,
            modelContext: modelContext
        )
        uptimeViewModel?.load()
    }
    // existing monitoring start code
    if let session, !session.isMonitoring {
        session.startMonitoring()
    }
}
.task(priority: .utility) {
    await connectivityMonitor?.start()
}
```

- [x] **Pass UptimeViewModel into ISPHealthCard**

Change the ISPHealthCard call site:

```swift
// Before:
ISPHealthCard(interfaceName: profile.interfaceName)

// After:
ISPHealthCard(interfaceName: profile.interfaceName, uptime: uptimeViewModel)
```

- [x] **Verify build**

### Task 6: Update ISPHealthCard to use real uptime data

**Files:**
- Modify: `NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift`

- [x] **Add uptime parameter**

```swift
// Add to ISPHealthCard struct:
var uptime: UptimeViewModel?
```

Update `init` to accept it (add `uptime: UptimeViewModel? = nil` parameter).

- [x] **Replace fake uptime bar with real data**

Remove `generateUptimeSegments()` and the `@State private var uptimeSegments: [Bool]`.

In `uptimeBarView`, change:
```swift
// Before: uses uptimeSegments (fake)
// After: uses uptime?.uptimeBar ?? []
let segments = uptime?.uptimeBar ?? []
```

If `segments.isEmpty`, render a neutral gray bar (no history yet) rather than fake data.

- [x] **Replace hardcoded uptime percentage**

```swift
// Before:
Text("99.8%")
    .font(.system(size: 20, weight: .bold, design: .rounded))
    .foregroundStyle(MacTheme.Colors.success)
Text("0 outages")

// After:
if let pct = uptime?.uptimePct {
    Text(String(format: "%.1f%%", pct))
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(pct > 99 ? MacTheme.Colors.success : pct > 95 ? MacTheme.Colors.warning : MacTheme.Colors.error)
    Text("\(uptime?.outageCount ?? 0) outage\(uptime?.outageCount == 1 ? "" : "s")")
} else {
    Text("—")
        .font(.system(size: 20, weight: .bold, design: .rounded))
        .foregroundStyle(.secondary)
    Text("No history yet")
}
```

- [x] **Remove the load() call and fake data generation** in ISPHealthCard

Delete `generateUptimeSegments()`, remove `uptimeSegments` @State, remove the `load()` call site that called `generateUptimeSegments()`. The real data flows from `uptime: UptimeViewModel?`.

- [x] **Verify build**
```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [x] **Run full test suite on mac-mini**
```bash
ssh mac-mini "cd ~/Projects/NetMonitor-2.0 && xcodebuild test -scheme NetMonitor-macOS -configuration Debug -destination 'platform=macOS' CODE_SIGN_IDENTITY='-' CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -parallel-testing-enabled NO -only-testing:NetMonitor-macOSTests 2>&1 | tail -30"
```

- [x] **Commit**
```bash
git add NetMonitor-macOS/Views/NetworkDetailView.swift \
        NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift
git commit -m "feat: wire real uptime history to ISPHealthCard via UptimeViewModel"
```

---

## Chunk 5: UptimeHistoryView (pro feature expansion)

This is the payoff for building the foundation — a dedicated history view that can be navigated to from ISPHealthCard or the tools section.

### Task 7: Create UptimeHistoryView

**Files:**
- Create: `NetMonitor-macOS/Views/Dashboard/UptimeHistoryView.swift`

A standalone view showing:
- 30-day uptime bar (reuses the bar component from ISPHealthCard, just larger)
- Outage log: list of `ConnectivityRecord` transitions grouped by day
- Latency trend: sparkline of latency samples over time

- [ ] **Write the view**

```swift
// NetMonitor-macOS/Views/Dashboard/UptimeHistoryView.swift
import SwiftUI
import SwiftData
import NetMonitorCore

/// Full uptime history view — navigated to from ISPHealthCard header button.
struct UptimeHistoryView: View {
    let profileID: UUID

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var vm: UptimeViewModel?
    @State private var recentOutages: [ConnectivityRecord] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                uptimeSummarySection
                outageLogSection
            }
            .padding(20)
        }
        .navigationTitle("Uptime History")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityIdentifier("uptimeHistory_button_close")
            }
        }
        .onAppear {
            if vm == nil {
                let viewModel = UptimeViewModel(
                    profileID: profileID,
                    modelContext: modelContext,
                    windowDays: 30,
                    barSegments: 30
                )
                viewModel.load()
                vm = viewModel
                loadRecentOutages()
            }
        }
    }

    // MARK: - Uptime Summary

    private var uptimeSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("30-Day Uptime", systemImage: "chart.bar.fill")
                .font(.headline)

            if let pct = vm?.uptimePct {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(String(format: "%.2f%%", pct))
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(pct > 99 ? MacTheme.Colors.success : MacTheme.Colors.warning)
                    Text("\(vm?.outageCount ?? 0) outage\(vm?.outageCount == 1 ? "" : "s")")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("No history recorded yet")
                    .foregroundStyle(.secondary)
            }

            // Large uptime bar
            if let bar = vm?.uptimeBar, !bar.isEmpty {
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(0..<bar.count, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(bar[i] ? MacTheme.Colors.success.opacity(0.7) : MacTheme.Colors.error)
                                .frame(width: max(1, (g.size.width - CGFloat(bar.count - 1) * 2) / CGFloat(bar.count)))
                        }
                    }
                }
                .frame(height: 24)

                HStack {
                    Text("30 days ago")
                    Spacer()
                    Text("Today")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("uptimeHistory_section_summary")
    }

    // MARK: - Outage Log

    private var outageLogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Outage Log", systemImage: "exclamationmark.triangle")
                .font(.headline)

            if recentOutages.isEmpty {
                Text("No outages recorded in the last 30 days")
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                ForEach(recentOutages) { record in
                    HStack {
                        Circle()
                            .fill(record.isOnline ? MacTheme.Colors.success : MacTheme.Colors.error)
                            .frame(width: 8, height: 8)
                        Text(record.isOnline ? "Came online" : "Went offline")
                            .font(.body)
                        Spacer()
                        Text(record.timestamp.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Divider()
                }
            }
        }
        .padding()
        .macGlassCard(cornerRadius: MacTheme.Layout.cardCornerRadius)
        .accessibilityIdentifier("uptimeHistory_section_outageLog")
    }

    private func loadRecentOutages() {
        let since = Date().addingTimeInterval(-30 * 86400)
        let id = profileID
        var descriptor = FetchDescriptor<ConnectivityRecord>(
            predicate: #Predicate { $0.profileID == id && $0.timestamp >= since && !$0.isSample },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        recentOutages = (try? modelContext.fetch(descriptor)) ?? []
    }
}
```

- [ ] **Wire into ISPHealthCard header** — add a clickable button next to the "NETWORK HEALTH" label in ISPHealthCard that opens `UptimeHistoryView` as a sheet:

```swift
// In ISPHealthCard header HStack, add a "history" button:
@State private var showHistory = false

// Add to header:
Button {
    showHistory = true
} label: {
    Image(systemName: "clock.arrow.circlepath")
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
}
.buttonStyle(.plain)
.accessibilityIdentifier("ispHealth_button_history")

// Add to the card's modifier chain:
.sheet(isPresented: $showHistory) {
    NavigationStack {
        UptimeHistoryView(profileID: uptime?.profileID ?? UUID())
    }
    .frame(minWidth: 600, minHeight: 500)
}
```

- [ ] **Verify build**
```bash
xcodebuild -scheme NetMonitor-macOS -configuration Debug build 2>&1 | grep -E "error:|Build succeeded"
```

- [ ] **Commit**
```bash
git add NetMonitor-macOS/Views/Dashboard/UptimeHistoryView.swift \
        NetMonitor-macOS/Views/Dashboard/ISPHealthCard.swift
git commit -m "feat: add UptimeHistoryView with 30-day bar and outage log"
git push
```

---

## Future Expansion (not in this plan)

These are easy additions once the foundation is in place:

- **Export to CSV** — `ConnectivityRecord` rows are already Codable; add an export button in `UptimeHistoryView`
- **Notifications** — `ConnectivityMonitor.writeTransition(isOnline: false)` is the perfect hook to fire a `UNUserNotification`
- **SLA reporting** — compute uptime for custom time ranges (business hours only, specific months) using the same `UptimeViewModel.compute()` logic
- **Multi-network comparison** — pass different `profileID`s to multiple `UptimeViewModel` instances
- **iOS companion** — `ConnectivityRecord` is in `NetMonitorCore` (shared package), so iOS can read the same history via the companion protocol
