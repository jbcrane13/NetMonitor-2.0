import BackgroundTasks
import Foundation
import Testing
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
