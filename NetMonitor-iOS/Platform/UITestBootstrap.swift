import Foundation
import NetMonitorCore
import NetworkScanKit
import PDFKit
import SwiftData
import UIKit
import os

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

    // MARK: - Timeline event fixtures (#453)

    /// With `UITEST_SEED_EVENTS=1`, replaces the saved Timeline events with two devices that
    /// joined and one that left, seconds ago, for the dashboard brief and the Timeline
    /// summary. Events persist across launches, so the old ones are cleared first.
    static func seedEventsIfNeeded() {
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_SEED_EVENTS"] == "1", !hasSeededEvents else { return }
        hasSeededEvents = true
        let events = NetworkEventService.shared
        events.clearAll()
        let now = Date()
        // Seconds before now, so they fall under "Today" whatever time the test runs.
        let seeded: [(NetworkEventType, String, String?, TimeInterval)] = [
            (.deviceJoined, "Device Joined: UITest Camera", "192.168.1.50", 30),
            (.deviceJoined, "Device Joined: UITest Speaker", "192.168.1.51", 20),
            (.deviceLeft, "Device Left: 192.168.1.30", nil, 10)
        ]
        for (type, title, details, secondsAgo) in seeded {
            let severity: NetworkEventSeverity = type == .deviceLeft ? .warning : .success
            events.log(NetworkEvent(type: type, timestamp: now.addingTimeInterval(-secondsAgo), title: title, details: details, severity: severity))
        }
    }

    private static var hasSeededEvents = false

    // MARK: - Event history migration fixtures (#491)

    /// Titles of the two valid events in the `--seed-legacy-events` blob, newest first.
    static let legacySeedTitles = ["Legacy: Device Joined: Old Printer", "Legacy: Scan Complete"]
    /// Title of the blob's element that doesn't decode as an event; it must not appear.
    static let legacyCorruptTitle = "Legacy: Corrupt element"

    /// Runs before `NetworkEventService.shared` loads. UI tests keep legacy events in their own
    /// UserDefaults suite (`HistoryFileLocation.legacyDefaults`), never the app's. A history
    /// reset also drops them there, so later UI tests don't migrate an earlier test's seed again.
    /// `--seed-legacy-events` then stores the blob builds before #491 wrote: two events around
    /// one corrupt element, for the migration test.
    static func prepareEventHistoryIfNeeded() {
        seedHealthSamplesIfNeeded()
        let location = HistoryFileLocation.current
        guard isUITesting, let defaults = location.legacyDefaults, defaults != .standard else { return }
        let key = NetworkEventService.legacyDefaultsKey
        if location.resetRequested {
            defaults.removeObject(forKey: key)
        }
        guard ProcessInfo.processInfo.arguments.contains("--seed-legacy-events") else { return }
        let now = Date().timeIntervalSinceReferenceDate
        let blob = """
        [{"id":"\(UUID())","type":"deviceJoined","timestamp":\(now - 120),"title":"\(legacySeedTitles[0])","severity":"success"},
        {"id":"not-a-uuid","type":"deviceJoined","title":"\(legacyCorruptTitle)"},
        {"id":"\(UUID())","type":"scanComplete","timestamp":\(now - 180),"title":"\(legacySeedTitles[1])","severity":"info"}]
        """
        defaults.set(Data(blob.utf8), forKey: key)
    }

    /// `--log-test-event "<title>"` logs one event at launch and saves it at once, so a relaunch
    /// can check it was kept.
    static func logTestEventIfRequested() {
        let args = ProcessInfo.processInfo.arguments
        guard isUITesting, let flag = args.firstIndex(of: "--log-test-event"), args.indices.contains(flag + 1) else { return }
        NetworkEventService.shared.log(type: .toolRun, title: args[flag + 1])
        NetworkEventService.shared.flush()
    }

    // MARK: - Health history fixtures (#491 S5)

    /// With `UITEST_SEED_HEALTH_SAMPLES=<n>`, replaces the health history with `n` samples for
    /// this device's network (`HealthScoreHistoryStore.seedForUITests`); under `UITEST_FAKE_DEVICES`,
    /// the UI-test network, which the dashboard then reads (#491 S4).
    private static func seedHealthSamplesIfNeeded() {
        guard isUITesting,
              let count = ProcessInfo.processInfo.environment["UITEST_SEED_HEALTH_SAMPLES"].flatMap(Int.init),
              let network = UITestFakeDeviceFeed.isEnabled ? networkProfileID : HealthSampleProbe.localNetworkProfileID()
        else { return }
        HealthScoreHistoryStore.shared.seedForUITests(count: count, networkProfileID: network)
    }

    /// The first page of an exported report, as an image and its text, for the UI-test
    /// preview in Settings: the share sheet doesn't show the PDF's pages.
    static func reportPreview(of data: Data) -> (image: UIImage, text: String, pageCount: Int)? {
        guard isUITesting, let document = PDFDocument(data: data), let page = document.page(at: 0) else { return nil }
        let image = page.thumbnail(of: CGSize(width: 612, height: 792), for: .mediaBox)
        return (image, page.string ?? "", document.pageCount)
    }
}

// MARK: - Event IDs fixtures (#491 S4)

extension UITestBootstrap {
    // The UI-test network (#491 D9). Under `UITEST_FAKE_DEVICES` it is the current network,
    // the fake discovery service stamps it on the fixture devices, and seeds use it.
    // swiftlint:disable:next force_unwrapping
    static let networkProfileID = UUID(uuidString: "00000491-0000-4000-8000-0000000000A4")!

    /// The custom name `--seed-timeline-device` gives the first fixture device's saved row.
    static let timelineDeviceName = "UITest Office Printer"

    /// `--uitesting-events`: run the event listener in a UI test, which otherwise doesn't.
    static var recordsEvents: Bool {
        isUITesting && ProcessInfo.processInfo.arguments.contains("--uitesting-events")
    }

    /// `--seed-timeline-device`: saves the first fixture device (its IP and MAC) on the UI-test
    /// network as "UITest Office Printer", so its events are named by the custom name.
    static func seedTimelineDeviceIfNeeded(in context: ModelContext) {
        guard isUITesting, ProcessInfo.processInfo.arguments.contains("--seed-timeline-device"), !hasSeededTimelineDevice else { return }
        hasSeededTimelineDevice = true
        guard let fixture = UITestFakeDeviceFeed().devices.first else { return }
        context.insert(LocalDevice(
            ipAddress: fixture.ipAddress,
            macAddress: fixture.macAddress ?? "",
            hostname: fixture.hostname,
            customName: timelineDeviceName,
            networkProfileID: networkProfileID
        ))
        do {
            try context.save()
        } catch {
            Logger.data.error("UI-test timeline device seed failed to save: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static var hasSeededTimelineDevice = false

    static let rangeEventTitles = (today: "UITest Event Today", tenDaysAgo: "UITest Event 10 Days Ago")

    /// `--seed-test-events`: one event today and one ten days ago on the UI-test network, for the
    /// Timeline's ranges (S3). Idempotent: never again into a history that already has them (the
    /// UI-test history survives a relaunch without a reset).
    static func seedRangeEventsIfNeeded(
        into eventService: any NetworkEventServiceProtocol = NetworkEventService.shared,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        now: Date = Date()
    ) {
        guard isUITesting, arguments.contains("--seed-test-events"),
              !eventService.events.contains(where: { $0.title == rangeEventTitles.today }) else { return }
        eventService.log(NetworkEvent(
            type: .connectivityChange, timestamp: now.addingTimeInterval(-10 * 86400),
            title: rangeEventTitles.tenDaysAgo, networkProfileID: networkProfileID
        ))
        // A minute ago, but never before today's midnight, so it is always "Today".
        let today = max(now.addingTimeInterval(-60), Calendar.current.startOfDay(for: now))
        eventService.log(NetworkEvent(
            type: .connectivityChange, timestamp: today,
            title: rangeEventTitles.today, networkProfileID: networkProfileID
        ))
    }

}
