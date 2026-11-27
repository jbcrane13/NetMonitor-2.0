import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
import UserNotifications
@testable import NetMonitor_iOS

/// #603 through the iPhone's real consumers: a reconcile that applies a scan delivers its device
/// events once, to the Timeline (`EventListenerService`), the scheduled-scan alerts
/// (`BackgroundTaskService`) and the scan diff (`ScheduledScanViewModel`). Every test uses its own
/// dispatcher, store and scan history.
@Suite("Device events on iPhone", .serialized)
@MainActor
final class DeviceEventConsumerTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated let suiteName = "DeviceEventConsumerTests.\(UUID().uuidString)"
    let dispatcher = DeviceEventDispatcher()
    let timeline = SpyNetworkEventService()
    let container: ModelContainer
    let listener: EventListenerService

    init() throws {
        let schema = AppModelStore.schema
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        listener = EventListenerService(eventService: timeline, discoveryService: MockDeviceDiscoveryService(), dispatcher: dispatcher)
        listener.start()
    }

    deinit {
        // The listener's subscription ends with it (owner-tied), so no stop is needed here.
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }

    var history: ScanHistory {
        ScanHistory(defaults: defaults)
    }

    /// `index` scans after the start, 10 minutes apart: three missed scans also pass the grace interval.
    func time(_ index: Int) -> Date {
        start.addingTimeInterval(Double(index) * 600)
    }

    func seen(_ ip: String, name: String?, mac: String? = nil) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: name, vendor: nil, macAddress: mac, latency: 3, discoveredAt: start, source: .local,
            networkProfileID: home
        )
    }

    var router: DiscoveredDevice {
        seen("192.168.1.1", name: "router", mac: "00:1B:A9:00:00:01")
    }

    /// A background scan's path: reconciled and published (`reconcileAndPublish`); its alerts come
    /// from the device-event notifier, as every applied reconcile's do, awaited as the task awaits them.
    func backgroundScan(_ devices: [DiscoveredDevice], at index: Int, alerts service: BackgroundTaskService) async {
        BackgroundTaskService.reconcileAndPublish(
            devices, scanDate: time(index), network: home, in: container, history: history, summaries: SavedDeviceSummaryModel(),
            defaults: defaults, reloadWidget: false, dispatcher: dispatcher, now: time(index)
        )
        await service.deviceEventAlertsPosted()
    }

    /// The alerts service, notifying from this suite's dispatcher, as the app's does from launch.
    func alertService(_ poster: EventAlertPoster) -> BackgroundTaskService {
        let service = BackgroundTaskService(
            registerTask: { _, _, _ in false },
            notifications: NotificationService(poster: poster, defaults: defaults),
            insightService: MockInsightService(isAvailable: false),
            isScanning: { false }
        )
        service.notifyDeviceEvents(from: dispatcher)
        return service
    }

    /// Turns the scheduled-scan alert toggles on for one test.
    func withScanAlertsOn(_ body: () async throws -> Void) async rethrows {
        let keys = ["scheduledScan_enabled", "scheduledScan_notifyNew", "scheduledScan_notifyMissing"]
        let originals = keys.map { UserDefaults.standard.object(forKey: $0) }
        keys.forEach { UserDefaults.standard.set(true, forKey: $0) }
        defer { zip(keys, originals).forEach { restoreDefault(.standard, key: $0, to: $1) } }
        try await body()
    }

    func deviceEntries() -> [String] {
        timeline.loggedEvents.filter { [.deviceJoined, .deviceLeft].contains($0.type) }.map(\.title)
    }

    func rows() throws -> [LocalDevice] {
        try ModelContext(container).fetch(FetchDescriptor<LocalDevice>())
    }

    // MARK: - #603 acceptance

    @Test("DHCP reuse without MACs: the newcomer joins, the old device leaves after grace, in the Timeline and the alerts")
    func dhcpReuseJoinsThenLeaves() async throws {
        let poster = EventAlertPoster()
        let service = alertService(poster)
        try await withScanAlertsOn {
        await backgroundScan([router, seen("192.168.1.30", name: "office-printer")], at: 0, alerts: service)
        #expect(deviceEntries().isEmpty, "the network's first scan is the baseline")

        // DHCP gave the printer's address to a phone; neither has a readable MAC.
        await backgroundScan([router, seen("192.168.1.30", name: "pixel-8")], at: 1, alerts: service)
        #expect(deviceEntries() == ["Device Joined: pixel-8"], "a newcomer, not the printer changed")
        let joined = try #require(timeline.loggedEvents.first { $0.type == .deviceJoined })
        let phone = try #require(try rows().first { $0.hostname == "pixel-8" })
        #expect(joined.deviceID == phone.id)
        #expect(joined.details == "192.168.1.30")
        #expect(joined.networkProfileID == home)
        #expect(poster.requests.map(\.content.title) == ["New Device Detected"])

        await backgroundScan([router, seen("192.168.1.30", name: "pixel-8")], at: 2, alerts: service)
        #expect(deviceEntries() == ["Device Joined: pixel-8"], "the printer is within grace")
        await backgroundScan([router, seen("192.168.1.30", name: "pixel-8")], at: 3, alerts: service)

        #expect(deviceEntries() == ["Device Joined: pixel-8", "Device Left: office-printer"])
        let left = try #require(timeline.loggedEvents.first { $0.type == .deviceLeft })
        let printer = try #require(try rows().first { $0.hostname == "office-printer" })
        #expect(left.deviceID == printer.id)
        #expect(poster.requests.map(\.content.title) == ["New Device Detected", "Target Down"], "one alert for each change")
        #expect(poster.requests.last?.content.body == "office-printer (192.168.1.30) is not responding")
        }
    }

    // MARK: - Notifications from every applied reconcile (#619)

    @Test("A device that joins in a foreground scan notifies once; the same scan in the background and the next one don't repeat it")
    func foregroundJoinNotifiesOnce() async throws {
        let poster = EventAlertPoster()
        let service = alertService(poster)
        try await withScanAlertsOn {
            try reconcile([router], at: 0)
            let scan = [router, seen("192.168.1.57", name: "pixel-8")]
            try reconcile(scan, at: 1)
            await service.deviceEventAlertsPosted()
            #expect(poster.requests.map(\.content.title) == ["New Device Detected"], "the foreground scan notifies")

            await backgroundScan(scan, at: 1, alerts: service)
            await backgroundScan(scan, at: 2, alerts: service)
            #expect(poster.requests.map(\.content.title) == ["New Device Detected"], "once")
        }
    }

    @Test("A device crossing grace in a foreground scan notifies once; a following background scan doesn't repeat it")
    func foregroundGraceNotifiesOnce() async throws {
        let poster = EventAlertPoster()
        let service = alertService(poster)
        try await withScanAlertsOn {
            let printer = seen("192.168.1.30", name: "office-printer", mac: "00:1B:A9:00:00:30")
            try reconcile([router, printer], at: 0)
            for index in 1 ... 3 {
                try reconcile([router], at: index)
            }
            await service.deviceEventAlertsPosted()
            #expect(poster.requests.map(\.content.title) == ["Target Down"])

            await backgroundScan([router], at: 3, alerts: service)
            await backgroundScan([router], at: 4, alerts: service)
            #expect(poster.requests.map(\.content.title) == ["Target Down"], "once")
        }
    }

    @Test("Scan alerts follow the user's toggles")
    func alertsFollowToggles() async throws {
        let poster = EventAlertPoster()
        let service = alertService(poster)
        try await withScanAlertsOn {
            UserDefaults.standard.set(false, forKey: "scheduledScan_notifyNew")
            try reconcile([router], at: 0)
            try reconcile([router, seen("192.168.1.57", name: "pixel-8")], at: 1)
            await service.deviceEventAlertsPosted()
            #expect(poster.requests.isEmpty)
        }
    }

    @Test("Without scheduled scanning on, a foreground join notifies nothing, as on main (#619)")
    func scanAlertsNeedScheduledScanning() async throws {
        let poster = EventAlertPoster()
        let service = alertService(poster)
        try await withScanAlertsOn {
            UserDefaults.standard.set(false, forKey: "scheduledScan_enabled")
            try reconcile([router], at: 0)
            try reconcile([router, seen("192.168.1.57", name: "pixel-8")], at: 1)
            await service.deviceEventAlertsPosted()
            #expect(poster.requests.isEmpty)
        }
    }

    @Test("A device back online is logged with the Mac's wording, once")
    func backOnline() throws {
        let printer = seen("192.168.1.30", name: "office-printer", mac: "00:1B:A9:00:00:30")
        for index in 0 ... 3 {
            try reconcile(index == 0 ? [router, printer] : [router], at: index)
        }
        try reconcile([router, printer], at: 4)
        #expect(deviceEntries() == ["Device Left: office-printer", "Device Back Online: office-printer"])
        #expect(timeline.loggedEvents.filter { $0.title.hasPrefix("Device Back Online: ") }.map(\.type) == [.deviceJoined])
    }

    @Test("A Mac with two interfaces under one Bonjour name joins as one device, named once")
    func groupJoinsOnce() throws {
        try reconcile([router], at: 0)
        let claims = { (ip: String) in [HostClaim(host: "studio-mac.local", service: "Studio", address: ip)] }
        try reconcile([
            router,
            DiscoveredDevice(ipAddress: "192.168.1.13", hostname: "studio-mac", vendor: nil, macAddress: "00:1B:A9:00:00:13", latency: 2,
                             discoveredAt: start, source: .bonjour, networkProfileID: home, bonjourClaims: claims("192.168.1.13")),
            DiscoveredDevice(ipAddress: "192.168.1.60", hostname: "studio-mac", vendor: nil, macAddress: "00:1B:A9:00:00:60", latency: 1,
                             discoveredAt: start, source: .bonjour, networkProfileID: home, bonjourClaims: claims("192.168.1.60"))
        ], at: 1)
        #expect(deviceEntries() == ["Device Joined: studio-mac"])
        let device = try #require(try DeviceGroups.project(rows()).first { $0.isGroup })
        #expect(timeline.loggedEvents.first { $0.type == .deviceJoined }?.deviceID == device.primary.id)
    }

    @Test("Foreground and background reconciles of one scan log once and alert once, whichever applies it")
    func raceDeliversOnce() async throws {
        let poster = EventAlertPoster()
        let service = alertService(poster)
        try await withScanAlertsOn {
            try reconcile([router], at: 0)
            // The foreground updater gets there first; the background reconcile of the same scan is skipped.
            let scan = [router, seen("192.168.1.57", name: "pixel-8")]
            try reconcile(scan, at: 1)
            let saved = BackgroundTaskService.reconcileAndPublish(
                scan, scanDate: time(1), network: home, in: container, history: history, summaries: SavedDeviceSummaryModel(),
                defaults: defaults, reloadWidget: false, dispatcher: dispatcher, now: time(1)
            )
            #expect(saved, "the background reconcile is skipped, not failed")
            await service.deviceEventAlertsPosted()

            #expect(deviceEntries() == ["Device Joined: pixel-8"])
            #expect(poster.requests.map(\.content.title) == ["New Device Detected"])
        }
    }

    // MARK: - Paths that log nothing

    @Test("A scan reconciled again (skipped) logs and alerts nothing")
    func skippedReconcileIsQuiet() async throws {
        let poster = EventAlertPoster()
        let service = alertService(poster)
        try await withScanAlertsOn {
            try reconcile([router], at: 0)
            try reconcile([router, seen("192.168.1.57", name: "pixel-8")], at: 1)
            await service.deviceEventAlertsPosted()
            let outcome = try reconcile([router, seen("192.168.1.58", name: "other")], at: 1)
            await service.deviceEventAlertsPosted()
            #expect(outcome == .skipped)
            #expect(deviceEntries() == ["Device Joined: pixel-8"])
            #expect(poster.requests.map(\.content.title) == ["New Device Detected"], "nothing for the skipped reconcile")
        }
    }

    @Test("A device held for detail (a row saved without a network at its address) makes no row and logs nothing")
    func heldForDetailIsQuiet() throws {
        let context = ModelContext(container)
        let legacy = LocalDevice(ipAddress: "192.168.1.30", macAddress: "", hostname: "office-printer", networkProfileID: nil)
        legacy.lastSeen = time(1)
        context.insert(legacy)
        try context.save()
        try reconcile([router], at: 0)
        try reconcile([router, seen("192.168.1.30", name: "office-printer")], at: 1)
        #expect(deviceEntries().isEmpty)
        #expect(try rows().count == 2, "the router and the legacy row: no second printer")
    }

    @Test("A row saved without a network, adopted by its real MAC, never joins")
    func adoptedLegacyRowIsQuiet() throws {
        let context = ModelContext(container)
        let legacy = LocalDevice(ipAddress: "192.168.1.40", macAddress: "00:1B:A9:00:00:40", hostname: "living-room", networkProfileID: nil)
        context.insert(legacy)
        try context.save()
        try reconcile([router], at: 0)
        try reconcile([router, seen("192.168.1.40", name: "living-room", mac: "00:1B:A9:00:00:40")], at: 1)
        #expect(deviceEntries().isEmpty)
        #expect(try rows().first { $0.id == legacy.id }?.networkProfileID == home, "adopted, not duplicated")
    }

    @Test("A listener logs device events from creation, before start(): a background launch's scan reaches the Timeline")
    func listensBeforeStart() throws {
        let early = SpyNetworkEventService()
        let unstarted = EventListenerService(eventService: early, discoveryService: MockDeviceDiscoveryService(), dispatcher: dispatcher)
        #expect(!unstarted.isRunning)
        try reconcile([router], at: 0)
        try reconcile([router, seen("192.168.1.57", name: "pixel-8")], at: 1)
        #expect(early.loggedEvents.map(\.title) == ["Device Joined: pixel-8"])
    }

    @Test("A listener that goes away stops listening")
    func releasedListenerUnsubscribes() throws {
        let gone = SpyNetworkEventService()
        var listener: EventListenerService? = EventListenerService(
            eventService: gone, discoveryService: MockDeviceDiscoveryService(), dispatcher: dispatcher
        )
        weak var released = listener
        listener = nil
        #expect(released == nil)
        try reconcile([router], at: 0)
        try reconcile([router, seen("192.168.1.57", name: "pixel-8")], at: 1)
        #expect(gone.loggedEvents.isEmpty)
        #expect(deviceEntries() == ["Device Joined: pixel-8"], "the suite's own listener still logs")
    }

    @Test("A stopped listener logs nothing more")
    func stoppedListenerIsQuiet() throws {
        try reconcile([router], at: 0)
        listener.stop()
        try reconcile([router, seen("192.168.1.57", name: "pixel-8")], at: 1)
        #expect(deviceEntries().isEmpty)
    }

    // MARK: - A store written by 2.3

    @Test("A 2.3 store's first scan is a quiet baseline; the next scan's newcomer is the only join")
    func v23StoreBaseline() throws {
        let fixture = try #require(Bundle(for: DeviceEventFixtureToken.self).url(forResource: "ios-v2.3-default", withExtension: "store"))
        let directory = FileManager.default.temporaryDirectory.appending(path: "nm-events-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "default.store")
        try FileManager.default.copyItem(at: fixture, to: url)
        let schema = AppModelStore.schema
        let store = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none)])
        // The fixture's network, studio (online, real MAC), printer (offline, no MAC) and a TV saved
        // without a network (cached, real MAC), all last seen in 2026-09.
        let fixtureNetwork = try #require(UUID(uuidString: "22222222-2222-2222-2222-222222222222"))
        let scanTime = Date(timeIntervalSince1970: 1_790_000_000 + 86400)
        func scanned(_ ip: String, _ name: String?, _ mac: String?) -> DiscoveredDevice {
            DiscoveredDevice(ipAddress: ip, hostname: name, vendor: nil, macAddress: mac, latency: 2, discoveredAt: scanTime, source: .local,
                             networkProfileID: fixtureNetwork)
        }
        let scan = [
            scanned("192.168.1.20", "Studio", "00:11:22:33:44:55"), scanned("192.168.1.30", nil, nil),
            scanned("192.168.1.40", "living-room.local", "AA:BB:CC:00:11:22"), scanned("192.168.1.50", "new-phone", nil)
        ]
        let reconciler = ScanReconciler(context: ModelContext(store), history: history, dispatcher: dispatcher)
        guard case let .applied(_, _, baseline) = try reconciler.reconcile(scan, networkProfileID: fixtureNetwork, scanDate: scanTime, now: scanTime)
        else {
            Issue.record("the 2.3 store's first scan should apply")
            return
        }
        #expect(baseline.isEmpty, "\(baseline.map(\.kind))")
        #expect(deviceEntries().isEmpty)

        let later = scanTime.addingTimeInterval(600)
        guard case let .applied(_, _, next) = try reconciler.reconcile(
            scan + [scanned("192.168.1.60", "guest-laptop", nil)], networkProfileID: fixtureNetwork, scanDate: later, now: later
        ) else {
            Issue.record("the next scan should apply")
            return
        }
        #expect(next.map(\.kind) == [.joined])
        #expect(next.map(\.name) == ["guest-laptop"])
        #expect(deviceEntries() == ["Device Joined: guest-laptop"], "no existing row joins")
    }

    // MARK: - Helpers

    @discardableResult
    // MARK: - Manual grouping (#619 verification)

    @Test("Same device as… joins an offline device to an online one: the Timeline gets Back Online once, and Undo adds nothing")
    func manualUnionLogsBackOnlineOnce() throws {
        let wired = seen("192.168.1.10", name: "studio", mac: "00:1B:A9:00:00:10")
        let wifi = seen("192.168.1.40", name: "studio-wifi", mac: "00:1B:A9:00:00:40")
        _ = try reconcile([router], at: 0)
        _ = try reconcile([router, wired, wifi], at: 1)
        for index in 2 ... 4 {
            _ = try reconcile([router, wifi], at: index)
        }
        #expect(deviceEntries().last == "Device Left: studio")

        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<LocalDevice>())
        let wifiRow = try #require(rows.first { $0.ipAddress == "192.168.1.40" })
        let wiredRow = try #require(rows.first { $0.ipAddress == "192.168.1.10" })
        let viewModel = DeviceDetailViewModel(
            deviceDiscoveryService: MockDeviceDiscoveryService(), references: [], clock: { [start] in start }, dispatcher: dispatcher,
            joinClock: .forTests
        )
        viewModel.loadDevice(id: wifiRow.id, context: context)
        viewModel.groupWith(DeviceGroups.project([wiredRow])[0])
        #expect(deviceEntries().filter { $0.hasPrefix("Device Back Online: ") } == ["Device Back Online: studio-wifi"])

        viewModel.undoGrouping()
        _ = try reconcile([router, wifi], at: 5)
        #expect(deviceEntries().filter { $0.hasPrefix("Device Back Online: ") }.count == 1, "Undo and the next scan add nothing")
    }

    func reconcile(_ devices: [DiscoveredDevice], at index: Int) throws -> ScanReconciler.Outcome {
        try ScanReconciler(context: ModelContext(container), history: history, dispatcher: dispatcher)
            .reconcile(devices, networkProfileID: home, scanDate: time(index), now: time(index))
    }
}

/// Records the alerts the scheduled scan posts.
@MainActor
final class EventAlertPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

private final class DeviceEventFixtureToken {}

// MARK: - The scheduled-scan screen's diff

@Suite("Scheduled scan diff from device events (#603)", .serialized)
@MainActor
final class ScheduledScanDiffTests {
    let home = UUID()
    let start = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated let suiteName = "ScheduledScanDiffTests.\(UUID().uuidString)"
    let dispatcher = DeviceEventDispatcher()
    let container: ModelContainer

    init() throws {
        let schema = AppModelStore.schema
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
    }

    deinit {
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
    }

    func device(_ ip: String, _ name: String) -> DiscoveredDevice {
        DiscoveredDevice(ipAddress: ip, hostname: name, vendor: nil, macAddress: nil, latency: 3, discoveredAt: start, source: .local,
                         networkProfileID: home)
    }

    @Test("Run Scan Now shows the scan's diff once the real updater reconciles it, and keeps it in the history once")
    func runScanNowShowsTheReconciledDiff() async throws {
        let discovery = MockDeviceDiscoveryService()
        let history = try ScanHistory(defaults: #require(UserDefaults(suiteName: suiteName)))
        let updater = DeviceRecordUpdater(
            discoveryService: discovery,
            reconciler: ScanReconciler(context: ModelContext(container), history: history, dispatcher: dispatcher),
            currentNetworkProfileID: { nil },
            joinClock: .forTests
        )
        let viewModel = ScheduledScanViewModel(
            scheduler: ScanSchedulerService(dispatcher: dispatcher), discovery: discovery, currentNetwork: { nil }, dispatcher: dispatcher
        )

        discovery.discoveredDevices = [device("192.168.1.1", "router")]
        discovery.lastScanDate = start
        updater.handleScanChange()
        #expect(viewModel.lastDiff == nil, "the baseline delivers nothing")

        let scanDate = start.addingTimeInterval(600)
        discovery.discoveredDevices = [device("192.168.1.1", "router"), device("192.168.1.57", "pixel-8")]
        discovery.lastScanDate = scanDate
        await viewModel.runScanNow()
        #expect(viewModel.lastDiff?.scannedAt == scanDate)
        #expect(viewModel.lastDiff?.hasChanges == false, "not reconciled yet: no changes shown")
        updater.handleScanChange()

        #expect(viewModel.lastDiff?.newDevices.map(\.displayName) == ["pixel-8"])
        #expect(viewModel.scanHistory.count == 1)
        updater.handleScanChange()
        #expect(viewModel.scanHistory.count == 1, "a scan already reconciled adds nothing")
    }

    @Test("Reopened after a change-free scan, the screen shows that scan with no changes, not the older diff (#619)")
    func reopenedAfterQuietScanShowsItsTime() throws {
        let history = try ScanHistory(defaults: #require(UserDefaults(suiteName: suiteName)))
        let reconciler = ScanReconciler(context: ModelContext(container), history: history, dispatcher: dispatcher)
        let scheduler = ScanSchedulerService(dispatcher: dispatcher)
        try reconciler.reconcile([device("192.168.1.1", "router")], networkProfileID: home, scanDate: start, now: start)
        let joined = start.addingTimeInterval(600), quiet = start.addingTimeInterval(1200)
        let scan = [device("192.168.1.1", "router"), device("192.168.1.57", "pixel-8")]
        try reconciler.reconcile(scan, networkProfileID: home, scanDate: joined, now: joined)
        try reconciler.reconcile(scan, networkProfileID: home, scanDate: quiet, now: quiet)
        #expect(scheduler.getLastScanDiff()?.scannedAt == joined, "the scheduler keeps the last diff with changes")

        let viewModel = ScheduledScanViewModel(
            scheduler: scheduler, discovery: MockDeviceDiscoveryService(), currentNetwork: { nil }, dispatcher: dispatcher,
            latestScan: { [home] in history.lastScanTime(for: home) }
        )
        #expect(viewModel.lastDiff?.scannedAt == quiet)
        #expect(viewModel.lastDiff?.hasChanges == false)
    }

    @Test("A diff that arrives before Run Scan Now returns is kept")
    func earlyDiffIsKept() async throws {
        let discovery = MockDeviceDiscoveryService()
        let history = try ScanHistory(defaults: #require(UserDefaults(suiteName: suiteName)))
        let reconciler = ScanReconciler(context: ModelContext(container), history: history, dispatcher: dispatcher)
        let viewModel = ScheduledScanViewModel(
            scheduler: ScanSchedulerService(dispatcher: dispatcher), discovery: discovery, currentNetwork: { nil }, dispatcher: dispatcher
        )
        try reconciler.reconcile([device("192.168.1.1", "router")], networkProfileID: home, scanDate: start, now: start)
        let scanDate = start.addingTimeInterval(600)
        try reconciler.reconcile(
            [device("192.168.1.1", "router"), device("192.168.1.57", "pixel-8")], networkProfileID: home, scanDate: scanDate, now: scanDate
        )
        discovery.lastScanDate = scanDate
        await viewModel.runScanNow()
        #expect(viewModel.lastDiff?.newDevices.map(\.displayName) == ["pixel-8"])
        #expect(viewModel.scanHistory.count == 1)
    }
}
