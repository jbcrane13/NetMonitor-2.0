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
        seedHeatmapSurveyIfNeeded()
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
            "netmonitor.deviceSuggestions",
            // Saved devices' missed-scan counts (#582); the store is in memory under UI tests.
            ScanHistory.storageKey
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
            // The demo is a scheduled scan's alert, which needs scheduled scanning on (#619).
            UserDefaults.standard.set(true, forKey: "scheduledScan_enabled")
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
            (.deviceJoined, DeviceTimelineTitle.title(DeviceTimelineTitle.joined, name: "UITest Camera"), "192.168.1.50", 30),
            (.deviceJoined, DeviceTimelineTitle.title(DeviceTimelineTitle.joined, name: "UITest Speaker"), "192.168.1.51", 20),
            (.deviceLeft, DeviceTimelineTitle.title(DeviceTimelineTitle.left, name: "192.168.1.30"), nil, 10)
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
    /// network as "UITest Office Printer", offline, so the next scan logs it back online (#603: a
    /// saved device never "joins") under the custom name.
    static func seedTimelineDeviceIfNeeded(in context: ModelContext) {
        guard isUITesting, ProcessInfo.processInfo.arguments.contains("--seed-timeline-device"), !hasSeededTimelineDevice else { return }
        hasSeededTimelineDevice = true
        guard let fixture = UITestFakeDeviceFeed().devices.first else { return }
        context.insert(LocalDevice(
            ipAddress: fixture.ipAddress,
            macAddress: fixture.macAddress ?? "",
            hostname: fixture.hostname,
            customName: timelineDeviceName,
            status: .offline,
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

// MARK: - Heatmap advisor fixtures (#455)

extension UITestBootstrap {
    /// The heatmap advisor's insight service under `UITEST_INSIGHT`: "answer" answers with
    /// `HeatmapAdvisorUITestFixture.answer`, "unavailable" is never available. Nil otherwise, and
    /// always in release builds.
    static var heatmapInsightService: (any InsightServiceProtocol)? {
        #if DEBUG
        guard isUITesting else { return nil }
        switch ProcessInfo.processInfo.environment["UITEST_INSIGHT"] {
        case "answer": return FixedAnswerInsightService(answer: HeatmapAdvisorUITestFixture.answer)
        case "unavailable": return UnavailableInsightService()
        default: return nil
        }
        #else
        return nil
        #endif
    }

    /// With `UITEST_SEED_HEATMAP=1` (Debug builds), saves the finished weak-corner survey to
    /// Documents, where Open Survey lists it.
    static func seedHeatmapSurveyIfNeeded() {
        #if DEBUG
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_SEED_HEATMAP"] == "1" else { return }
        let project = HeatmapAdvisorUITestFixture.project()
        guard let url = HeatmapFileManager().autoSaveURL(for: project.name) else { return }
        try? FileManager.default.removeItem(at: url)
        try? HeatmapFileManager().save(project: project, to: url)
        #endif
    }
}

// MARK: - Label capture fixtures (#456)

extension UITestBootstrap {
    /// What the UI-test label prints, and what the stand-in model reads from it. Its MAC is on
    /// no fixture device, so Save doesn't meet the duplicate-MAC case.
    static let testLabel = (
        maker: "Northwind Networks", model: "NW-AC1200", serial: "NW12K4471093", mac: "00:1E:42:7A:9C:31"
    )

    /// `UITEST_LABEL_IMAGE=1`: the label sheet reads ``testLabelImage`` instead of asking for a
    /// photo, since the simulator has no camera.
    static var usesTestLabelImage: Bool {
        isUITesting && ProcessInfo.processInfo.environment["UITEST_LABEL_IMAGE"] == "1"
    }

    /// `UITEST_LABEL_MODEL`: "answer" makes a stand-in model fill ``testLabel`` (still checked
    /// against the real OCR text), "unavailable" turns the model off. Nil otherwise.
    static var labelExtractor: (any LabelFieldExtractorProtocol)? {
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_LABEL_MODEL"] == "answer" else { return nil }
        return FixedLabelFieldExtractor(answer: LabelFields(
            status: .found, maker: testLabel.maker, model: testLabel.model, serial: testLabel.serial, mac: testLabel.mac
        ))
    }

    static var labelInsightService: (any InsightServiceProtocol)? {
        guard isUITesting else { return nil }
        switch ProcessInfo.processInfo.environment["UITEST_LABEL_MODEL"] {
        case "answer": return FixedAnswerInsightService(answer: "")
        case "unavailable": return UnavailableInsightService()
        default: return nil
        }
    }

    /// A photo-like device label with ``testLabel``'s values, drawn at launch; real OCR reads it.
    static func testLabelImage() -> CGImage? {
        let size = CGSize(width: 900, height: 520)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor(white: 0.55, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor(white: 0.96, alpha: 1).setFill()
            context.fill(CGRect(x: 60, y: 50, width: 780, height: 420))
            let lines: [(String, UIFont)] = [
                (testLabel.maker, .boldSystemFont(ofSize: 34)),
                ("Model: \(testLabel.model)", .monospacedSystemFont(ofSize: 30, weight: .regular)),
                ("S/N: \(testLabel.serial)", .monospacedSystemFont(ofSize: 30, weight: .regular)),
                ("MAC: \(testLabel.mac)", .monospacedSystemFont(ofSize: 30, weight: .regular)),
                ("Input: 12V 1.5A", .monospacedSystemFont(ofSize: 22, weight: .regular))
            ]
            for (index, line) in lines.enumerated() {
                (line.0 as NSString).draw(
                    at: CGPoint(x: 90, y: 80 + index * 70),
                    withAttributes: [.font: line.1, .foregroundColor: UIColor.black]
                )
            }
        }
        return image.cgImage
    }
}

// MARK: - Troubleshooter fixtures (#451)

extension UITestBootstrap {
    /// `UITEST_TROUBLESHOOT` under a UI test: "answer", "hold" or "unavailable"
    /// (`TroubleshootUITestFixture.Mode`). Nil otherwise, and always in release builds.
    static var troubleshootMode: String? {
        #if DEBUG
        guard isUITesting else { return nil }
        return ProcessInfo.processInfo.environment["UITEST_TROUBLESHOOT"]
        #else
        return nil
        #endif
    }
}

// MARK: - Plain-English rules (#450)

extension UITestBootstrap {
    /// The rule parser under `UITEST_INSIGHT`: "answer" reads rules from the real model's recorded
    /// answers (`FixedRuleIntentParser.uiTest`), "unavailable" is never available. Nil otherwise,
    /// and always in release builds.
    static var ruleParser: (any RuleIntentParsing)? {
        #if DEBUG
        guard isUITesting else { return nil }
        switch ProcessInfo.processInfo.environment["UITEST_INSIGHT"] {
        case "answer": return FixedRuleIntentParser.uiTest
        case "unavailable": return UnavailableRuleIntentParser()
        default: return nil
        }
        #else
        return nil
        #endif
    }

    static let rulePrinter = (name: "uitest-printer", ip: "192.168.77.20")

    /// Under UI tests (Debug builds), a draft's port check reaches no real network: no port answers.
    static var ruleProbe: MonitoringTargetProbe? {
        #if DEBUG
        guard isUITesting else { return nil }
        return MonitoringTargetProbe { _, _, _ in false }
        #else
        return nil
        #endif
    }

    /// With `UITEST_RULE_SCAN_DEVICES=1` (Debug builds), the UI-test scan also finds a printer that
    /// has no saved row: "office-laser", with IPP 631 and 9100 open, so its type is inferred and a
    /// target can probe it (#571, #572).
    static var ruleScanDevices: [DiscoveredDevice] {
        #if DEBUG
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_RULE_SCAN_DEVICES"] == "1" else { return [] }
        return [DiscoveredDevice(
            ipAddress: "192.168.1.30", hostname: "office-laser", vendor: nil, macAddress: "02:00:00:01:00:30",
            latency: 4, discoveredAt: Date(), source: .local, networkProfileID: networkProfileID, openPorts: [631, 9100]
        )]
        #else
        return []
        #endif
    }

    /// With `UITEST_SEED_PAST_DEVICE=1` (Debug builds, #583): an offline TV on the UI-test network
    /// last seen 8 days before the scan clock's start, a past device the list hides behind
    /// "Show past devices". Never twice.
    static func seedPastDeviceIfNeeded(in context: ModelContext) {
        #if DEBUG
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_SEED_PAST_DEVICE"] == "1",
              !((try? context.fetch(FetchDescriptor<LocalDevice>()))?.contains { $0.ipAddress == pastDeviceIP } ?? false)
        else { return }
        let row = LocalDevice(
            ipAddress: pastDeviceIP, macAddress: "02:00:00:01:00:50", hostname: "uitest-old-tv",
            deviceType: .tv, status: .offline, networkProfileID: networkProfileID
        )
        row.lastSeen = scanClockStart.addingTimeInterval(-8 * 86400)
        context.insert(row)
        try? context.save()
        #endif
    }

    static let pastDeviceIP = "192.168.1.50"

    /// With `UITEST_SEED_RULE_DEVICES=1` (Debug builds): a printer and a NAS on the UI-test
    /// network, for describing rules about "the printer". Never twice.
    static func seedRuleDevicesIfNeeded(in context: ModelContext) {
        #if DEBUG
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_SEED_RULE_DEVICES"] == "1",
              !((try? context.fetch(FetchDescriptor<LocalDevice>()))?.contains { $0.ipAddress == rulePrinter.ip } ?? false)
        else { return }
        context.insert(LocalDevice(
            ipAddress: rulePrinter.ip, macAddress: "02:00:00:77:00:20", hostname: rulePrinter.name,
            deviceType: .printer, networkProfileID: networkProfileID
        ))
        context.insert(LocalDevice(
            ipAddress: "192.168.77.40", macAddress: "02:00:00:77:00:40", hostname: "uitest-nas",
            // A scan found SMB open, so its target has a port to probe (#572).
            deviceType: .storage, openPorts: [445], networkProfileID: networkProfileID
        ))
        try? context.save()
        #endif
    }
}

// MARK: - A device with two interfaces (#594)

extension UITestBootstrap {
    /// The device `UITEST_SEED_DEVICE_GROUP=1` saves: its primary's address and name, and its other
    /// interface, which is the UI-test scan's uitest-device-3; the primary has a serial. Fixture values only.
    static let groupDevice = (
        name: "UITest Studio Mac", primaryIP: "192.168.1.60", primaryNotes: "Wired port in the studio",
        memberIP: "192.168.1.13", memberNotes: "Wi-Fi interface", serial: "UITESTSERIAL594"
    )

    /// With `UITEST_SEED_DEVICE_GROUP=1` (Debug builds): one device on the UI-test network with two
    /// interfaces, grouped through `DeviceGroupWriter`. The primary (192.168.1.60, named, with notes)
    /// is offline and isn't in the UI-test scan; the other interface is uitest-device-3's address and
    /// MAC, so a scan finds only it. Never twice.
    static func seedDeviceGroupIfNeeded(in context: ModelContext) {
        #if DEBUG
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_SEED_DEVICE_GROUP"] == "1",
              !((try? context.fetch(FetchDescriptor<LocalDevice>()))?.contains { $0.ipAddress == groupDevice.primaryIP } ?? false)
        else { return }
        let primary = LocalDevice(
            ipAddress: groupDevice.primaryIP, macAddress: "02:00:00:94:00:60", hostname: "uitest-studio-wired",
            deviceType: .computer, customName: groupDevice.name, status: .offline, notes: groupDevice.primaryNotes,
            networkProfileID: networkProfileID
        )
        primary.lastSeen = scanClockStart.addingTimeInterval(-3600)
        primary.serialNumber = groupDevice.serial
        primary.serialSource = IdentitySource.userConfirmed.rawValue
        let member = LocalDevice(
            ipAddress: groupDevice.memberIP, macAddress: "AA:BB:CC:DD:EE:03", hostname: "uitest-device-3",
            status: .offline, notes: groupDevice.memberNotes, networkProfileID: networkProfileID
        )
        member.lastSeen = scanClockStart.addingTimeInterval(-7200)
        context.insert(primary)
        context.insert(member)
        do {
            try context.save()
            try DeviceGroupWriter(context: context).group([primary.id, member.id], primary: primary.id, source: .user)
        } catch {
            Logger.data.error("UI-test device group seed failed to save: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }
}

// MARK: - Grouping (#594 PR2)

extension UITestBootstrap {
    /// The two interfaces `UITEST_FAKE_BONJOUR_GROUP=1` adds to the UI-test scan, both answering for
    /// one strong Bonjour name. Fixture values only.
    static let bonjourGroupScan = (host: "uitest-studio.local", wifiIP: "192.168.1.70", wiredIP: "192.168.1.71")

    /// With `UITEST_FAKE_BONJOUR_GROUP=1` (Debug builds): a Mac answering the UI-test scan at two
    /// addresses, each with its own MAC, both claiming `bonjourGroupScan.host`, so the scan groups
    /// them into one device. `enabled` is for the unit test that checks the fixture.
    static func bonjourGroupScanDevices(
        enabled: Bool = isUITesting && ProcessInfo.processInfo.environment["UITEST_FAKE_BONJOUR_GROUP"] == "1"
    ) -> [DiscoveredDevice] {
        #if DEBUG
        guard enabled else { return [] }
        let scan = bonjourGroupScan
        return [(scan.wifiIP, "02:00:00:94:00:70"), (scan.wiredIP, "02:00:00:94:00:71")].map { ip, mac in
            DiscoveredDevice(
                ipAddress: ip, hostname: "uitest-studio", vendor: nil, macAddress: mac, latency: 3, discoveredAt: Date(), source: .bonjour,
                networkProfileID: networkProfileID, bonjourClaims: [HostClaim(host: scan.host, service: "UITest Studio", address: ip)]
            )
        }
        #else
        return []
        #endif
    }

    /// The two saved devices `UITEST_SEED_GROUP_SUGGESTION=1` adds. Fixture values only.
    static let suggestionPair = (
        host: "uitest-library.local", wiredIP: "192.168.1.80", wiredName: "uitest-library-wired",
        wifiIP: "192.168.1.81", wifiName: "uitest-library-wifi"
    )

    /// With `UITEST_SEED_GROUP_SUGGESTION=1` (Debug builds): two saved devices on the UI-test network,
    /// not in the UI-test scan, that answered for `suggestionPair.host` an hour ago, so device detail
    /// suggests they are one device. Never twice.
    static func seedGroupSuggestionIfNeeded(in context: ModelContext) {
        #if DEBUG
        let pair = suggestionPair
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_SEED_GROUP_SUGGESTION"] == "1",
              !((try? context.fetch(FetchDescriptor<LocalDevice>()))?.contains { $0.ipAddress == pair.wiredIP } ?? false)
        else { return }
        // Against the wall clock, which the suggestion's 30-day window reads.
        let seen = Date().addingTimeInterval(-3600)
        for (ip, name, mac) in [(pair.wiredIP, pair.wiredName, "02:00:00:94:00:80"), (pair.wifiIP, pair.wifiName, "02:00:00:94:00:81")] {
            let row = LocalDevice(ipAddress: ip, macAddress: mac, hostname: name, deviceType: .storage, networkProfileID: networkProfileID)
            row.bonjourHost = pair.host
            row.bonjourHostSeenAt = seen
            row.lastSeen = seen
            context.insert(row)
        }
        do {
            try context.save()
        } catch {
            Logger.data.error("UI-test group suggestion seed failed to save: \(error.localizedDescription, privacy: .public)")
        }
        #endif
    }
}

// MARK: - Saved devices follow scans (#582)

extension UITestBootstrap {
    /// With `UITEST_SCAN_CLOCK=1`: the clock the device-record updater stamps scans with. The first
    /// scan is at 08:00 on 2026-11-20 (local time), each later one 10 minutes after the previous,
    /// so a test sees "last seen" at a known time and the grace interval pass without waiting.
    static var scanClock: (@MainActor () -> Date)? {
        #if DEBUG
        guard isUITesting, ProcessInfo.processInfo.environment["UITEST_SCAN_CLOCK"] == "1" else { return nil }
        return {
            defer { scanClockTicks += 1 }
            let now = scanClockStart.addingTimeInterval(Double(scanClockTicks) * 600)
            lastScanClockReading = now
            return now
        }
        #else
        return nil
        #endif
    }

    // swiftlint:disable:next force_unwrapping
    static let scanClockStart = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 8))!
    private static var scanClockTicks = 0
    private static var lastScanClockReading: Date?

    /// The time saved devices' presence is shown as of (#583): the wall clock; under
    /// `UITEST_SCAN_CLOCK=1` the latest scan's time on that clock (its start before any scan).
    /// `UITEST_PRESENCE_OFFSET=<seconds>` moves it on, so a network reads "Not checked recently".
    static func presenceNow() -> Date {
        #if DEBUG
        guard isUITesting else { return Date() }
        let environment = ProcessInfo.processInfo.environment
        let base = environment["UITEST_SCAN_CLOCK"] == "1" ? lastScanClockReading ?? scanClockStart : Date()
        return base.addingTimeInterval(environment["UITEST_PRESENCE_OFFSET"].flatMap(TimeInterval.init) ?? 0)
        #else
        return Date()
        #endif
    }

    /// With `UITEST_SCAN_DROP_LAST=1`: scans after the first no longer find uitest-device-4. Always
    /// false in release builds.
    static var dropsLastDeviceAfterFirstScan: Bool {
        #if DEBUG
        isUITesting && ProcessInfo.processInfo.environment["UITEST_SCAN_DROP_LAST"] == "1"
        #else
        false
        #endif
    }
}

// MARK: - Ask your network (#452)

extension UITestBootstrap {
    /// `UITEST_ASK` under a UI test: "answer", "hold" or "unavailable" (`AskUITestFixture.Mode`).
    /// Nil otherwise, and always in release builds.
    static var askMode: String? {
        #if DEBUG
        guard isUITesting else { return nil }
        return ProcessInfo.processInfo.environment["UITEST_ASK"]
        #else
        return nil
        #endif
    }

    /// Under `UITEST_ASK`: the fixture's printer and two joins this week, for the Ask flows.
    static func seedAskIfNeeded(in context: ModelContext) {
        #if DEBUG
        guard askMode != nil else { return }
        AskUITestFixture.seed(into: context, events: NetworkEventService.shared)
        #endif
    }
}
