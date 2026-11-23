import BackgroundTasks
import Foundation
import NetMonitorCore
import NetworkScanKit
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_iOS

// BGTaskScheduler itself is never exercised here: `submit` for an identifier with no registered
// launch handler raises an Objective-C exception that Swift cannot catch, which crashed the test
// runner for months (#309). Scheduling behaviour is asserted through the injected seams instead.

@MainActor
struct BackgroundTaskServiceTests {

    @Test("Task identifier strings are well-formed reverse-DNS identifiers")
    func taskIdentifiersAreWellFormed() {
        // Verify the static identifier constants are non-empty and follow reverse-DNS format
        let refresh = BackgroundTaskService.refreshTaskIdentifier
        let sync = BackgroundTaskService.syncTaskIdentifier
        let scan = BackgroundTaskService.scheduledNetworkScanTaskIdentifier

        #expect(!refresh.isEmpty, "Refresh task identifier must not be empty")
        #expect(!sync.isEmpty, "Sync task identifier must not be empty")
        #expect(!scan.isEmpty, "Scheduled scan task identifier must not be empty")

        // All identifiers should contain dots (reverse-DNS format)
        #expect(refresh.contains("."), "Refresh identifier should be reverse-DNS: \(refresh)")
        #expect(sync.contains("."), "Sync identifier should be reverse-DNS: \(sync)")
        #expect(scan.contains("."), "Scan identifier should be reverse-DNS: \(scan)")
    }

    @Test("All three task identifiers are distinct")
    func taskIdentifiersAreDistinct() {
        let ids: Set<String> = [
            BackgroundTaskService.refreshTaskIdentifier,
            BackgroundTaskService.syncTaskIdentifier,
            BackgroundTaskService.scheduledNetworkScanTaskIdentifier
        ]
        #expect(ids.count == 3, "All three task identifiers must be unique")
    }

    @Test("Shared singleton initializes without crashing")
    func sharedSingletonIsAccessible() {
        // INTEGRATION GAP: BGTaskScheduler.shared.submit() requires the app to be
        // registered with the system scheduler — cannot fully invoke in unit test sandbox.
        // This smoke test verifies no crash on singleton access.
        let service = BackgroundTaskService.shared
        _ = service
    }

    @Test("scheduleRefreshTask submits a refresh request once tasks are registered")
    func scheduleRefreshTaskSubmitsAfterRegistration() {
        let recorder = ScheduledRequestRecorder()
        let service = recorder.makeService()
        let defaults = UserDefaults.standard
        let key = AppSettings.Keys.backgroundRefreshEnabled
        let original = defaults.object(forKey: key)
        defer { restoreDefault(defaults, key: key, to: original) }
        defaults.set(true, forKey: key)

        service.registerTasks()
        let before = Date()
        service.scheduleRefreshTask()

        #expect(recorder.submitted.count == 1)
        let request = recorder.submitted.first
        #expect(request is BGAppRefreshTaskRequest)
        #expect(request?.identifier == BackgroundTaskService.refreshTaskIdentifier)
        // BGTaskScheduler enforces a 15-minute minimum; the service must never ask for less.
        #expect((request?.earliestBeginDate ?? .distantPast) >= before.addingTimeInterval(15 * 60 - 1))
        #expect(recorder.cancelled.isEmpty)
    }

    @Test("submitting before registerTasks() is refused without raising (#309)")
    func submitBeforeRegistrationIsRefused() {
        // Real BGTaskScheduler.submit raises an uncatchable ObjC exception for an unregistered
        // identifier — the previous version of this test crashed the whole test runner on it.
        let recorder = ScheduledRequestRecorder()
        let service = recorder.makeService()
        let defaults = UserDefaults.standard
        let key = AppSettings.Keys.backgroundRefreshEnabled
        let original = defaults.object(forKey: key)
        defer { restoreDefault(defaults, key: key, to: original) }
        defaults.set(true, forKey: key)

        service.scheduleRefreshTask()  // no registerTasks() first

        #expect(recorder.submitted.isEmpty, "submit must be refused until tasks are registered")
        #expect(recorder.cancelled.isEmpty)
    }
}

// MARK: - Model-worded scan alerts (#453)

@MainActor
private final class ScanAlertPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

/// Answers every request with its first key point, prefixed, and counts requests.
private final class KeyPointInsightService: InsightServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    let isAvailable: Bool
    init(isAvailable: Bool) { self.isAvailable = isAvailable }
    var requestCount: Int { lock.withLock { count } }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        lock.withLock { count += 1 }
        return AsyncStream { continuation in
            continuation.yield(.finished("Model: " + (request.observations.first ?? "")))
            continuation.finish()
        }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? { nil }
}

@Suite("Scheduled scan alerts worded on device (#453)", .serialized)
@MainActor
struct ScheduledScanAlertTextTests {
    let missing = DiscoveredDevice(
        ipAddress: "192.168.1.41", hostname: "Garage Camera", vendor: nil, macAddress: nil,
        latency: nil, discoveredAt: Date(), source: .local
    )
    let joined = DiscoveredDevice(
        ipAddress: "192.168.1.57", hostname: "Pixel-8", vendor: "Google", macAddress: nil,
        latency: nil, discoveredAt: Date(), source: .local
    )

    private func run(available: Bool, scanning: Bool = false) async -> ([UNNotificationRequest], Int) {
        let keys = ["scheduledScan_notifyNew", "scheduledScan_notifyMissing"]
        let originals = keys.map { UserDefaults.standard.object(forKey: $0) }
        keys.forEach { UserDefaults.standard.set(true, forKey: $0) }
        defer { zip(keys, originals).forEach { restoreDefault(.standard, key: $0, to: $1) } }
        let suite = "ScheduledScanAlertTextTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        defer { defaults.removePersistentDomain(forName: suite) }

        let poster = ScanAlertPoster()
        let insight = KeyPointInsightService(isAvailable: available)
        let service = BackgroundTaskService(
            registerTask: { _, _, _ in false },
            notifications: NotificationService(poster: poster, defaults: defaults),
            insightService: insight,
            isScanning: { scanning }
        )
        await service.notifyScanChanges(ScanDiff(newDevices: [joined], removedDevices: [missing], changedDevices: []))
        return (poster.requests, insight.requestCount)
    }

    @Test func newAndMissingDevicesGetModelBodiesUnderFixedTitles() async {
        let (requests, asked) = await run(available: true)
        #expect(asked == 2)
        #expect(requests.map(\.content.title) == ["New Device Detected", "Target Down"])
        #expect(requests.map(\.content.body) == [
            "Model: Pixel-8 joined the network for the first time.",
            "Model: Garage Camera (192.168.1.41) is not responding."
        ])
        #expect(requests.allSatisfy { $0.content.subtitle == NotificationService.generatedSubtitle })
    }

    @Test func unavailableModelSendsTodaysText() async {
        let (requests, asked) = await run(available: false)
        #expect(asked == 0)
        #expect(requests.map(\.content.body) == [
            "Pixel-8 (192.168.1.57) joined the network",
            "Garage Camera (192.168.1.41) is not responding"
        ])
        #expect(requests.allSatisfy { $0.content.subtitle.isEmpty })
    }

    @Test func noInferenceWhileAScanRuns() async {
        let (requests, asked) = await run(available: true, scanning: true)
        #expect(asked == 0)
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.content.subtitle.isEmpty })
    }
}

// MARK: - Shared test seam

/// Records what `BackgroundTaskService` asks the scheduler to do, so tests never touch the real
/// `BGTaskScheduler` — whose `submit` raises an uncatchable ObjC exception in a test host that has
/// not registered the identifier (#309). Also used by `BackgroundTaskServiceExtendedTests`.
@MainActor
final class ScheduledRequestRecorder {
    private(set) var registered: [String] = []
    private(set) var submitted: [BGTaskRequest] = []
    private(set) var cancelled: [String] = []

    func makeService() -> BackgroundTaskService {
        BackgroundTaskService(
            registerTask: { [self] identifier, _, _ in registered.append(identifier)
            return true
            },
            submitTask: { [self] request in submitted.append(request) },
            cancelTask: { [self] identifier in cancelled.append(identifier) }
        )
    }
}

@MainActor
func restoreDefault(_ defaults: UserDefaults, key: String, to original: Any?) {
    if let original {
        defaults.set(original, forKey: key)
    } else {
        defaults.removeObject(forKey: key)
    }
}
