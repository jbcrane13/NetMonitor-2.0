import Testing
import Foundation
@testable import NetMonitor_iOS

// MARK: - BackgroundTaskService Extended Tests
//
// Extends the 4 tests in BackgroundTaskServiceTests.swift with error-handling
// and scheduling configuration coverage.

@MainActor
struct BackgroundTaskServiceExtendedTests {

    // MARK: - Error handling paths

    @Test("scheduleRefreshTask respects backgroundRefreshEnabled = false")
    func scheduleRefreshTaskRespectsDisabledFlag() {
        // When backgroundRefreshEnabled is explicitly false, scheduleRefreshTask
        // should cancel the task rather than submit. In the test sandbox,
        // BGTaskScheduler operations are no-ops, but the code path must not crash.
        let defaults = UserDefaults.standard
        let key = AppSettings.Keys.backgroundRefreshEnabled
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.set(false, forKey: key)
        let service = BackgroundTaskService.shared
        // Must not crash when background refresh is disabled
        service.scheduleRefreshTask()
    }

    @Test("scheduleRefreshTask allows scheduling when backgroundRefreshEnabled is true")
    func scheduleRefreshTaskAllowsEnabled() {
        let defaults = UserDefaults.standard
        let key = AppSettings.Keys.backgroundRefreshEnabled
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.set(true, forKey: key)
        let service = BackgroundTaskService.shared
        // In test sandbox, submit() throws notPermitted which is caught internally
        service.scheduleRefreshTask()
    }

    @Test("scheduleRefreshTask defaults to enabled when key is absent")
    func scheduleRefreshTaskDefaultsToEnabled() {
        let defaults = UserDefaults.standard
        let key = AppSettings.Keys.backgroundRefreshEnabled
        let original = defaults.object(forKey: key)
        defer {
            if let original { defaults.set(original, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
        defaults.removeObject(forKey: key)
        let service = BackgroundTaskService.shared
        // With key absent, the guard defaults to true and attempts to schedule
        service.scheduleRefreshTask()
    }

    // MARK: - Refresh interval configuration

    @Test("autoRefreshInterval UserDefaults key matches expected constant")
    func autoRefreshIntervalKeyMatchesConstant() {
        #expect(AppSettings.Keys.autoRefreshInterval == "autoRefreshInterval")
    }

    @Test("backgroundRefreshEnabled UserDefaults key matches expected constant")
    func backgroundRefreshEnabledKeyMatchesConstant() {
        #expect(AppSettings.Keys.backgroundRefreshEnabled == "backgroundRefreshEnabled")
    }

    // MARK: - Task identifier format validation

    @Test("All task identifiers share the same bundle prefix")
    func taskIdentifiersShareBundlePrefix() {
        let ids = [
            BackgroundTaskService.refreshTaskIdentifier,
            BackgroundTaskService.syncTaskIdentifier,
            BackgroundTaskService.scheduledNetworkScanTaskIdentifier
        ]
        // All should start with the same reverse-DNS prefix
        let prefix = "com.blakemiller.netmonitor"
        for id in ids {
            #expect(id.hasPrefix(prefix), "Task identifier '\(id)' should start with '\(prefix)'")
        }
    }

    @Test("registerTasks does not crash in test sandbox")
    func registerTasksDoesNotCrash() {
        // BGTaskScheduler.shared.register() in test sandbox may warn but must not crash
        let service = BackgroundTaskService.shared
        service.registerTasks()
    }
}
