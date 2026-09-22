import BackgroundTasks
import Foundation
import Testing
@testable import NetMonitor_iOS

// MARK: - BackgroundTaskService Extended Tests
//
// Extends the 4 tests in BackgroundTaskServiceTests.swift with error-handling
// and scheduling configuration coverage.

@MainActor
struct BackgroundTaskServiceExtendedTests {

    // MARK: - Scheduling behaviour (through the injected seams — never the real BGTaskScheduler, #309)

    @Test("scheduleRefreshTask respects backgroundRefreshEnabled = false")
    func scheduleRefreshTaskRespectsDisabledFlag() {
        let defaults = UserDefaults.standard
        let key = AppSettings.Keys.backgroundRefreshEnabled
        let original = defaults.object(forKey: key)
        defer { restoreDefault(defaults, key: key, to: original) }
        defaults.set(false, forKey: key)

        let recorder = ScheduledRequestRecorder()
        let service = recorder.makeService()
        service.registerTasks()
        service.scheduleRefreshTask()

        // Disabled → cancel the pending request, never submit a new one.
        #expect(recorder.cancelled == [BackgroundTaskService.refreshTaskIdentifier])
        #expect(recorder.submitted.isEmpty)
    }

    @Test("scheduleRefreshTask allows scheduling when backgroundRefreshEnabled is true")
    func scheduleRefreshTaskAllowsEnabled() {
        let defaults = UserDefaults.standard
        let key = AppSettings.Keys.backgroundRefreshEnabled
        let original = defaults.object(forKey: key)
        defer { restoreDefault(defaults, key: key, to: original) }
        defaults.set(true, forKey: key)

        let recorder = ScheduledRequestRecorder()
        let service = recorder.makeService()
        service.registerTasks()
        service.scheduleRefreshTask()

        #expect(recorder.submitted.map(\.identifier) == [BackgroundTaskService.refreshTaskIdentifier])
        #expect(recorder.cancelled.isEmpty)
    }

    @Test("scheduleRefreshTask defaults to enabled when key is absent")
    func scheduleRefreshTaskDefaultsToEnabled() {
        let defaults = UserDefaults.standard
        let key = AppSettings.Keys.backgroundRefreshEnabled
        let original = defaults.object(forKey: key)
        defer { restoreDefault(defaults, key: key, to: original) }
        defaults.removeObject(forKey: key)

        let recorder = ScheduledRequestRecorder()
        let service = recorder.makeService()
        service.registerTasks()
        service.scheduleRefreshTask()

        // Key absent → treated as enabled → a refresh request is submitted.
        #expect(recorder.submitted.map(\.identifier) == [BackgroundTaskService.refreshTaskIdentifier])
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

    @Test("registerTasks registers every identifier exactly once")
    func registerTasksIsIdempotent() {
        var registeredIdentifiers: [String] = []
        let service = BackgroundTaskService { identifier, _, _ in
            registeredIdentifiers.append(identifier)
            return true
        }

        service.registerTasks()
        service.registerTasks()

        #expect(registeredIdentifiers == [
            BackgroundTaskService.refreshTaskIdentifier,
            BackgroundTaskService.syncTaskIdentifier,
            BackgroundTaskService.scheduledNetworkScanTaskIdentifier
        ])
    }
}
