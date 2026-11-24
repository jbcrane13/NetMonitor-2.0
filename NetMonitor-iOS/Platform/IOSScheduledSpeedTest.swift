import Foundation
import NetMonitorCore
import SwiftData
import os

/// Scheduled speed tests on iPhone (#398). They run only while the app is open:
/// a BGAppRefreshTask gets about 30 seconds, too short for a download and upload
/// test. Results are saved as `SpeedTestResult`, which `DataMaintenanceService`
/// already prunes by the data retention setting.
@MainActor
enum IOSScheduledSpeedTest {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "ScheduledSpeedTest")

    /// True while a scheduled test runs; a manual test won't start then.
    static var isTestRunning = false
    /// Manual tests in progress; a scheduled test won't start then.
    static var manualTestsRunning = 0

    /// Counts a manual test in and returns true, unless a scheduled or another manual test is
    /// running: the troubleshooter's speed test (#451) never runs over the Speed Test tool's.
    static func claimManualTest() -> Bool {
        guard !isTestRunning, manualTestsRunning == 0 else { return false }
        manualTestsRunning += 1
        return true
    }

    static func latestResultDate(in modelContext: ModelContext) -> Date? {
        var descriptor = FetchDescriptor<SpeedTestResult>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        descriptor.fetchLimit = 1
        return (try? modelContext.fetch(descriptor))?.first?.timestamp
    }

    /// Runs one test with `service` and saves it to `modelContext`.
    static func runScheduledTest(service: any SpeedTestServiceProtocol, modelContext: ModelContext) async {
        guard !isTestRunning else { return }
        isTestRunning = true
        defer { isTestRunning = false }
        do {
            let data = try await service.startTest()
            modelContext.insert(SpeedTestResult(
                downloadSpeed: data.downloadSpeed,
                uploadSpeed: data.uploadSpeed,
                latency: data.latency,
                jitter: data.jitter,
                serverName: data.serverName
            ))
            try modelContext.save()
            logger.notice("Scheduled speed test saved")
        } catch {
            logger.error("Scheduled speed test failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static func makeScheduler(
        modelContext: ModelContext,
        service: any SpeedTestServiceProtocol = SpeedTestService()
    ) -> ScheduledSpeedTestRunner {
        ScheduledSpeedTestRunner(
            lastRunAt: { latestResultDate(in: modelContext) },
            isRunning: { isTestRunning || manualTestsRunning > 0 },
            runTest: { await runScheduledTest(service: service, modelContext: modelContext) }
        )
    }
}
