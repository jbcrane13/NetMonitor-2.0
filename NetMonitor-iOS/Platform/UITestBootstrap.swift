import Foundation
import NetMonitorCore
import NetworkScanKit
import PDFKit
import SwiftData
import UIKit

@MainActor
enum UITestBootstrap {
    private static var hasConfigured = false

    static func configureIfNeeded() {
        guard isUITesting, !hasConfigured else { return }
        hasConfigured = true

        if ProcessInfo.processInfo.arguments.contains("--uitesting-reset") {
            resetDefaults()
        }

        applyDeterministicDefaults()
        TargetManager.shared.clearSelection()
        ToolActivityLog.shared.clear()
        startNotificationDemoIfRequested()
    }

    static var isUITesting: Bool {
        let args = ProcessInfo.processInfo.arguments
        if args.contains("--uitesting") || args.contains("--uitesting-reset") {
            return true
        }

        let env = ProcessInfo.processInfo.environment
        return env["UITEST_MODE"] == "1" ||
            env["XCUITest"] == "1" ||
            env["XCTestConfigurationFilePath"] != nil
    }

    private static func resetDefaults() {
        let defaults = UserDefaults.standard
        let keysToClear = [
            AppSettings.Keys.defaultPingCount,
            AppSettings.Keys.pingTimeout,
            AppSettings.Keys.portScanTimeout,
            AppSettings.Keys.dnsServer,
            AppSettings.Keys.dataRetentionDays,
            AppSettings.Keys.showDetailedResults,
            AppSettings.Keys.autoRefreshInterval,
            AppSettings.Keys.backgroundRefreshEnabled,
            AppSettings.Keys.selectedNetworkProfileID,
            AppSettings.Keys.targetDownAlertEnabled,
            AppSettings.Keys.highLatencyAlertEnabled,
            AppSettings.Keys.highLatencyThreshold,
            AppSettings.Keys.newDeviceAlertEnabled,
            AppSettings.Keys.selectedTheme,
            AppSettings.Keys.selectedAccentColor,
            AppSettings.Keys.webBrowserRecentURLs,
            "targetManager_savedTargets",
            "netmonitor.networkProfiles",
            "netmonitor.deviceSuggestions"
        ]

        for key in keysToClear {
            defaults.removeObject(forKey: key)
        }
    }

    private static func applyDeterministicDefaults() {
        let defaults = UserDefaults.standard
        defaults.set(4, forKey: AppSettings.Keys.defaultPingCount)
        defaults.set(5.0, forKey: AppSettings.Keys.pingTimeout)
        defaults.set(2.0, forKey: AppSettings.Keys.portScanTimeout)
        defaults.set("", forKey: AppSettings.Keys.dnsServer)
        defaults.set(30, forKey: AppSettings.Keys.dataRetentionDays)
        defaults.set(true, forKey: AppSettings.Keys.showDetailedResults)
        defaults.set(60, forKey: AppSettings.Keys.autoRefreshInterval)
        defaults.set(false, forKey: AppSettings.Keys.backgroundRefreshEnabled)
        defaults.set(true, forKey: AppSettings.Keys.targetDownAlertEnabled)
        defaults.set(false, forKey: AppSettings.Keys.highLatencyAlertEnabled)
        defaults.set(100, forKey: AppSettings.Keys.highLatencyThreshold)
        defaults.set(true, forKey: AppSettings.Keys.newDeviceAlertEnabled)
        defaults.set("dark", forKey: AppSettings.Keys.selectedTheme)
        defaults.set("cyan", forKey: AppSettings.Keys.selectedAccentColor)
    }

    // MARK: - Notification demo (#453)

    /// The device the notification demo reports missing.
    static let demoDevice = DiscoveredDevice(
        ipAddress: "192.168.1.41", hostname: "Garage Camera", vendor: nil, macAddress: nil,
        latency: nil, discoveredAt: Date(), source: .local
    )
    /// What the demo's stand-in model writes for it: grounded in the alert's facts.
    static let demoModelText = "Garage Camera (192.168.1.41) dropped off your network and is not answering."

    /// `--uitesting-notification-demo`: asks for notification permission, then, once the app is
    /// in the background, sends a scheduled scan's "device missing" alert through
    /// `BackgroundTaskService.notifyScanChanges`, the path a real scan uses. A stand-in model
    /// answers with `demoModelText`; `--uitesting-model-unavailable` makes it unavailable.
    private static func startNotificationDemoIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("--uitesting-notification-demo") else { return }
        let insight: any InsightServiceProtocol = args.contains("--uitesting-model-unavailable")
            ? UnavailableInsightService()
            : FixedAnswerInsightService(answer: demoModelText)
        Task {
            guard await NotificationService.shared.requestAuthorization() else { return }
            while UIApplication.shared.applicationState != .background {
                try? await Task.sleep(for: .milliseconds(200))
            }
            let backgroundTask = UIApplication.shared.beginBackgroundTask()
            let service = BackgroundTaskService(registerTask: { _, _, _ in false }, insightService: insight, isScanning: { false })
            await service.notifyScanChanges(ScanDiff(newDevices: [], removedDevices: [demoDevice], changedDevices: []))
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }

    // MARK: - PDF report fixtures (#453)

    /// The insight service a UI test picks with `UITEST_INSIGHT`: "answer" answers every
    /// request at once with `reportSummaryAnswer`, "unavailable" is never available. Nil
    /// (use the real service) otherwise and outside UI tests.
    static var insightService: (any InsightServiceProtocol)? {
        guard isUITesting else { return nil }
        switch ProcessInfo.processInfo.environment["UITEST_INSIGHT"] {
        case "answer": return FixedAnswerInsightService(answer: reportSummaryAnswer)
        case "unavailable": return UnavailableInsightService()
        default: return nil
        }
    }

    /// States no number, so it stays grounded whatever the seeded devices' status becomes.
    static let reportSummaryAnswer = "The app recorded the devices on this network; the key points above say what needs attention."

    /// With `UITEST_SEED_REPORT=1`, adds devices to the (in-memory) UI-test store so the
    /// report has something to summarize; one is offline, which gives a key point.
    static func seedReportDataIfNeeded(in context: ModelContext) {
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_SEED_REPORT"] == "1", !hasSeededReport else { return }
        hasSeededReport = true
        context.insert(LocalDevice(ipAddress: "192.168.1.1", macAddress: "AA:BB:CC:00:00:01", customName: "UITest Router", isGateway: true))
        context.insert(LocalDevice(ipAddress: "192.168.1.20", macAddress: "AA:BB:CC:00:00:02", customName: "UITest Laptop"))
        context.insert(LocalDevice(ipAddress: "192.168.1.30", macAddress: "AA:BB:CC:00:00:03", customName: "UITest Printer", status: .offline))
        try? context.save()
    }

    private static var hasSeededReport = false

    /// The first page of an exported report, as an image and its text, for the UI-test
    /// preview in Settings: the share sheet doesn't show the PDF's pages.
    static func reportPreview(of data: Data) -> (image: UIImage, text: String, pageCount: Int)? {
        guard isUITesting, let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        return (image, page.string ?? "", document.pageCount)
    }
}

/// Answers every request at once with a fixed text (UI tests only).
private struct FixedAnswerInsightService: InsightServiceProtocol {
    let answer: String
    var isAvailable: Bool { true }

    func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        AsyncStream { continuation in
            continuation.yield(.finished(answer))
            continuation.finish()
        }
    }

    func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? { nil }
}
