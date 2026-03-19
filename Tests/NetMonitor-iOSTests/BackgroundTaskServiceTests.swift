import Testing
import Foundation
@testable import NetMonitor_iOS

// Note: BGTaskScheduler registration can only be tested in a simulator/device context
// with a running app process. These tests verify service configuration and identifier
// format without actually scheduling tasks.

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

    @Test("scheduleRefreshTask does not crash when called outside app context")
    func scheduleRefreshTaskDoesNotCrash() {
        // INTEGRATION GAP: In the test sandbox, BGTaskScheduler.shared.submit() will
        // throw BGTaskScheduler.Error.notPermitted because tasks are not registered.
        // BackgroundTaskService.scheduleRefreshTask() already catches and logs this error,
        // so calling it here must not propagate an exception.
        let service = BackgroundTaskService.shared
        service.scheduleRefreshTask()
    }
}
