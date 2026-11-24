import Foundation
import NetMonitorCore
import SwiftData
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_macOS

@MainActor
private final class PlainRulePoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

@Suite("Plain-English rules on the Mac (#450)", .serialized)
@MainActor
struct PlainRuleMacTests {
    private let nasSentence = "Tell me if the NAS is down for more than five minutes"
    private let timing = RuleTiming(targetCheckInterval: 30)

    private func makeDefaults() -> (UserDefaults, String) {
        let suite = "PlainRuleMacTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite) ?? .standard, suite)
    }

    /// The caller keeps the container: a context whose container is released crashes.
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([NetworkTarget.self, TargetMeasurement.self, SessionRecord.self])
        let config = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func nas() -> LocalDevice {
        LocalDevice(ipAddress: "192.168.77.40", macAddress: "02:00:00:77:00:40", hostname: "uitest-nas", deviceType: .storage)
    }

    private func viewModel() -> PlainRuleMacViewModel {
        PlainRuleMacViewModel(parser: FixedRuleIntentParser.uiTest, timing: timing)
    }

    @Test func nothingIsSavedUntilConfirm() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let container = try makeContainer()
        let context = container.mainContext
        let device = nas()
        let model = viewModel()
        model.text = nasSentence

        await model.submit(devices: [device], targets: [], isScanning: false)

        #expect(model.draft?.rule.conditions.deviceID == device.id)
        #expect(model.addsTarget, "A target is offered and on by default")
        #expect(store.rules.isEmpty)
        #expect(AlertRuleStore(defaults: defaults).rules.isEmpty)
        #expect(try context.fetch(FetchDescriptor<NetworkTarget>()).isEmpty)

        model.cancel()
        #expect(model.draft == nil)
        #expect(AlertRuleStore(defaults: defaults).rules.isEmpty, "Cancel saves nothing")
    }

    @Test func confirmSavesTheRuleOnTheDevicesIdentityAndItsTarget() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let container = try makeContainer()
        let context = container.mainContext
        let device = nas()
        let model = viewModel()
        model.text = nasSentence
        await model.submit(devices: [device], targets: [], isScanning: false)

        model.confirm(store: store, context: context, session: nil)

        let saved = AlertRuleStore(defaults: defaults).rules
        #expect(saved.count == 1)
        #expect(saved.first?.trigger == .wentOffline)
        #expect(saved.first?.conditions == AlertRuleConditions(device: "02:00:00:77:00:40", deviceID: device.id))
        #expect(saved.first?.minimumDuration == 300)
        #expect(saved.first?.name == "Offline for 5 minutes")
        let targets = try context.fetch(FetchDescriptor<NetworkTarget>())
        #expect(targets.map(\.host) == ["192.168.77.40"])
        #expect(targets.first?.checkInterval == 30)
        #expect(model.draft == nil)
        #expect(model.text.isEmpty)
    }

    @Test func confirmWithoutTheTargetSavesOnlyTheRule() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try makeContainer()
        let context = container.mainContext
        let model = viewModel()
        model.text = nasSentence
        await model.submit(devices: [nas()], targets: [], isScanning: false)
        model.addsTarget = false

        model.confirm(store: AlertRuleStore(defaults: defaults), context: context, session: nil)

        #expect(AlertRuleStore(defaults: defaults).rules.count == 1)
        #expect(try context.fetch(FetchDescriptor<NetworkTarget>()).isEmpty)
    }

    /// Monitoring skips a turned-off target, so it doesn't count as monitoring the device: the
    /// draft offers to turn it back on, and confirming does that instead of adding a second one.
    @Test func aTurnedOffTargetIsOfferedAndTurnedBackOnAtConfirm() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try makeContainer()
        let context = container.mainContext
        let existing = NetworkTarget(name: "NAS web", host: "192.168.77.40", targetProtocol: .icmp, checkInterval: 120, isEnabled: false)
        context.insert(existing)
        try context.save()
        let model = viewModel()
        model.text = nasSentence

        await model.submit(devices: [nas()], targets: [existing], isScanning: false)

        #expect(model.draft?.hasTarget == false)
        #expect(model.addsTarget)
        #expect(model.reusesDisabledTarget)
        #expect(model.notes.contains { $0.contains("checks it every 2 minutes") }, "Notes: \(model.notes)")

        model.confirm(store: AlertRuleStore(defaults: defaults), context: context, session: nil)

        let targets = try context.fetch(FetchDescriptor<NetworkTarget>())
        #expect(targets.count == 1)
        #expect(targets.first?.isEnabled == true)
    }

    @Test func theNotesQuoteTheExistingTargetsOwnCheckInterval() async {
        let existing = NetworkTarget(name: "NAS", host: "192.168.77.40", targetProtocol: .icmp, checkInterval: 120, isEnabled: true)
        let model = viewModel()
        model.text = nasSentence

        await model.submit(devices: [nas()], targets: [existing], isScanning: false)

        #expect(model.draft?.hasTarget == true)
        #expect(!model.reusesDisabledTarget)
        #expect(model.notes == [
            "Fires once uitest-nas has been unreachable for 5 minutes, timed by its monitoring target, which checks it every 2 minutes."
        ])
    }

    @Test func thePrinterScanOpensThePortScannerPrefilledAndSavesNothing() async {
        let printer = LocalDevice(ipAddress: "192.168.77.20", macAddress: "00:1B:A9:77:00:20", hostname: "uitest-printer", deviceType: .printer)
        let model = viewModel()
        model.text = "scan web ports on the printer"
        await model.submit(devices: [nas(), printer], targets: [], isScanning: false)
        #expect(model.composer.outcome == .portScan(device: RuleDevice(printer), preset: .web))
        #expect(model.draft == nil)
    }

    @Test func unsupportedInputGivesTheMessage() async {
        let model = viewModel()
        model.text = "what's the weather"
        await model.submit(devices: [nas()], targets: [], isScanning: false)
        #expect(model.composer.outcome == .message(RuleIntent.unsupportedMessage))
        #expect(model.draft == nil)
    }

    /// Through the app's real rule alerts: the target's host is the NAS's row, so the event carries
    /// the NAS's identity, and the rule waits out its five minutes instead of firing at the first failure.
    @Test func aTargetGoingDownDoesNotFireAFiveMinuteRuleAtOnce() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        store.add(AlertRule(name: "Offline for 5 minutes", trigger: .wentOffline,
                            conditions: AlertRuleConditions(deviceID: device.id), minimumDuration: 300))
        device.customName = "Basement NAS"
        let poster = PlainRulePoster()
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults) {
            ([device], nil)
        }
        let target = UUID()
        func check(down: Bool) {
            alerts.handle(targetResult: TargetCheckOutcome(
                targetID: target, name: "NAS", host: "192.168.77.40", isReachable: false, latency: nil, wentDown: down, cameUp: false
            ))
        }

        check(down: true)
        check(down: false)
        #expect(poster.requests.isEmpty, "Not down for five minutes yet")
    }

    /// An HTTP target answering 503 is unreachable and still reports a latency on every check.
    /// The rule's clock must run through those checks and stop only when the target recovers.
    @Test func aTargetFailingWithALatencyFiresItsDurationRuleOnceTheTimeIsUp() throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        store.add(AlertRule(name: "Offline briefly", trigger: .wentOffline,
                            conditions: AlertRuleConditions(deviceID: device.id), minimumDuration: 0.2))
        let poster = PlainRulePoster()
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults) {
            ([device], nil)
        }
        let target = UUID()
        func check(reachable: Bool = false, wentDown: Bool = false, cameUp: Bool = false) {
            alerts.handle(targetResult: TargetCheckOutcome(
                targetID: target, name: "NAS", host: "192.168.77.40", isReachable: reachable, latency: 35, wentDown: wentDown, cameUp: cameUp
            ))
        }

        check(wentDown: true)
        check()
        #expect(poster.requests.isEmpty, "Not down long enough yet")
        Thread.sleep(forTimeInterval: 0.3)
        check()
        #expect(poster.requests.map(\.content.title) == ["Offline briefly"])
        check()
        #expect(poster.requests.count == 1, "Once per outage")

        check(reachable: true, cameUp: true)
        check(wentDown: true)
        #expect(poster.requests.count == 1, "A new outage starts a new clock")
    }

    @Test func aScanThatReportsTheDeviceOfflineFiresItsDurationRuleByIdentity() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        device.customName = "Basement NAS"
        store.add(AlertRule(name: "Offline for 5 minutes", trigger: .wentOffline,
                            conditions: AlertRuleConditions(deviceID: device.id), minimumDuration: 300))
        let poster = PlainRulePoster()
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults)
        // A scan reports offline after its grace period: last seen 15 minutes ago.
        let known = KnownDevice(macAddress: "02:00:00:77:00:40", ipAddress: "192.168.77.40", name: "uitest-nas",
                                firstSeen: Date().addingTimeInterval(-86400), lastSeen: Date().addingTimeInterval(-900))

        alerts.handle(deviceChanges: [.wentOffline(known)], devices: [device], networkID: nil)

        #expect(poster.requests.map(\.content.title) == ["Offline for 5 minutes"])
        #expect(poster.requests.first?.content.body == "Basement NAS went offline")
    }

    @Test func theRuleListNamesTheDeviceByItsCurrentName() {
        let device = nas()
        let rule = AlertRule(name: "Offline", trigger: .wentOffline,
                             conditions: AlertRuleConditions(device: "uitest-nas", deviceID: device.id), minimumDuration: 300)
        device.customName = "Basement NAS"
        #expect(RuleDescription.summary(rule, networks: [], devices: [device]) == "Goes offline · for 5 minutes · device Basement NAS")
        #expect(RuleDescription.summary(rule, networks: [], devices: []) == "Goes offline · for 5 minutes · device a removed device")
    }

}

// MARK: - #450 review

extension PlainRuleMacTests {
    private actor ReachableService: NetMonitor_macOS.NetworkMonitorService {
        func check(request: TargetCheckRequest) async throws -> MeasurementResult {
            MeasurementResult(targetID: request.id, timestamp: Date(), latency: 3, isReachable: true, errorMessage: nil)
        }
    }

    private func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
        let deadline = ContinuousClock.now + timeout
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    private func session(_ context: ModelContext) -> MonitoringSession {
        let stub = ReachableService()
        return MonitoringSession(modelContext: context, anyHTTPService: stub, anyICMPService: stub, anyTCPService: stub)
    }

    @Test func confirmCanStartMonitoringAfterSavingSoItChecksTheNewTarget() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let container = try makeContainer()
        let context = container.mainContext
        let monitoring = session(context)
        let model = viewModel()
        model.text = nasSentence
        await model.submit(devices: [nas()], targets: [], isScanning: false)
        #expect(model.usesTarget)
        #expect(model.startsMonitoring, "Offered and on by default while monitoring is stopped")

        model.confirm(store: store, context: context, session: monitoring, startMonitoring: true)

        #expect(monitoring.isMonitoring)
        let target = try #require(try context.fetch(FetchDescriptor<NetworkTarget>()).first)
        await waitUntil { monitoring.latestResults[target.id] != nil }
        #expect(monitoring.latestResults[target.id]?.isReachable == true, "The new target is checked")
        await monitoring.stopMonitoringAndWait()
    }

    @Test func confirmWithoutStartingLeavesMonitoringStopped() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let container = try makeContainer()
        let monitoring = session(container.mainContext)
        let model = viewModel()
        model.text = nasSentence
        await model.submit(devices: [nas()], targets: [], isScanning: false)
        model.confirm(store: AlertRuleStore(defaults: defaults), context: container.mainContext, session: monitoring, startMonitoring: false)
        #expect(!monitoring.isMonitoring)
    }

    @Test func theTargetARuleAddsIsLinkedToTheDevice() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let container = try makeContainer()
        let device = nas()
        let model = viewModel()
        model.text = nasSentence
        await model.submit(devices: [device], targets: [], isScanning: false)
        model.confirm(store: store, context: container.mainContext, session: nil)
        let target = try #require(try container.mainContext.fetch(FetchDescriptor<NetworkTarget>()).first)
        #expect(store.device(forTarget: target.id) == device.id)
        #expect(AlertRuleStore(defaults: defaults).device(forTarget: target.id) == device.id, "Saved")
    }

    /// The NAS moved to .41 and another device took its old address .40: checks of .40 are not the
    /// NAS's, so they never alert for it, and the target is moved to .41.
    @Test func aLinkedTargetFollowsItsDeviceAndNeverAlertsForTheOneOnItsOldAddress() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        device.ipAddress = "192.168.77.41"
        let newcomer = LocalDevice(ipAddress: "192.168.77.40", macAddress: "02:00:00:77:00:99", hostname: "newcomer", deviceType: .phone)
        store.add(AlertRule(name: "NAS offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: device.id)))
        store.add(AlertRule(name: "Phone offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: newcomer.id)))
        let target = UUID()
        store.link(target: target, to: device.id)
        let poster = PlainRulePoster()
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults) {
            ([device, newcomer], nil)
        }

        alerts.handle(targetResult: TargetCheckOutcome(
            targetID: target, name: "NAS", host: "192.168.77.40", isReachable: false, latency: nil, wentDown: true, cameUp: false
        ))
        #expect(poster.requests.isEmpty, "Neither the NAS nor the newcomer is alerted from the old address")
        #expect(alerts.movedHost(forTarget: target, checkedAt: "192.168.77.40") == "192.168.77.41")
        #expect(alerts.movedHost(forTarget: target, checkedAt: "192.168.77.41") == nil)

        alerts.handle(targetResult: TargetCheckOutcome(
            targetID: target, name: "NAS", host: "192.168.77.41", isReachable: false, latency: nil, wentDown: true, cameUp: false
        ))
        #expect(poster.requests.map(\.content.title) == ["NAS offline"])
    }

    /// On another network the NAS has no row, and its old private address is someone else's: the
    /// linked target's checks there are not the NAS's.
    @Test func aLinkedTargetsChecksOnAnotherNetworkAreNotItsDevices() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        let printer = LocalDevice(ipAddress: "192.168.77.40", macAddress: "02:00:00:77:00:98", hostname: "office-printer", deviceType: .printer)
        store.add(AlertRule(name: "NAS offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: device.id)))
        let target = UUID()
        store.link(target: target, to: device.id)
        let poster = PlainRulePoster()
        var devices = [printer]
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults) {
            (devices, nil)
        }
        func checkFails() {
            alerts.handle(targetResult: TargetCheckOutcome(
                targetID: target, name: "NAS", host: "192.168.77.40", isReachable: false, latency: nil, wentDown: true, cameUp: false
            ))
        }

        checkFails()
        #expect(poster.requests.isEmpty, "The NAS isn't on this network")

        devices = [device]
        checkFails()
        #expect(poster.requests.map(\.content.title) == ["NAS offline"], "Back on the NAS's network")
    }

    /// The NAS went offline and a phone took its address. The NAS's row keeps that address, but
    /// the scan shows the phone answering there, so the target's readings are not the NAS's.
    @Test func aLinkedTargetsChecksOfAnAddressAnotherDeviceTookAreNotItsDevices() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        device.status = .offline
        let phone = LocalDevice(ipAddress: "192.168.77.40", macAddress: "02:00:00:77:00:99", hostname: "phone", deviceType: .phone)
        phone.status = .online
        store.add(AlertRule(name: "NAS slow", trigger: .latencyAbove(milliseconds: 100), conditions: AlertRuleConditions(deviceID: device.id)))
        let target = UUID()
        store.link(target: target, to: device.id)
        let poster = PlainRulePoster()
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults) {
            ([device, phone], nil)
        }
        func slowReading() {
            alerts.handle(targetResult: TargetCheckOutcome(
                targetID: target, name: "NAS", host: "192.168.77.40", isReachable: true, latency: 400, wentDown: false, cameUp: false
            ))
        }

        slowReading()
        #expect(poster.requests.isEmpty, "The phone's latency is not the NAS's")

        device.status = .online
        phone.status = .offline
        slowReading()
        #expect(poster.requests.map(\.content.title) == ["NAS slow"], "The NAS answers at its address again")
    }

    private actor OldAddressDownService: NetMonitor_macOS.NetworkMonitorService {
        func check(request: TargetCheckRequest) async throws -> MeasurementResult {
            let reachable = request.host != "192.168.77.40"
            return MeasurementResult(targetID: request.id, timestamp: Date(), latency: reachable ? 3 : nil, isReachable: reachable, errorMessage: nil)
        }
    }

    /// The session and the app's alert wiring together: the NAS moved to .41, so the failed check
    /// of its old address .40 is neither saved in the NAS target's history nor alerted as down.
    @Test func aCheckOfTheAddressADeviceLeftIsNeitherSavedNorAlerted() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let container = try makeContainer()
        let context = container.mainContext
        let device = nas()
        device.ipAddress = "192.168.77.41"
        let target = NetworkTarget(name: "NAS", host: "192.168.77.40", targetProtocol: .icmp, checkInterval: 60)
        context.insert(target)
        try context.save()
        store.link(target: target.id, to: device.id)
        let poster = PlainRulePoster()
        let dispatcher = MacAlertDispatcher(
            service: NotificationService(poster: poster, defaults: defaults), store: store, defaults: defaults
        ) { ([device], nil) }
        let stub = OldAddressDownService()
        let monitoring = MonitoringSession(modelContext: context, anyHTTPService: stub, anyICMPService: stub, anyTCPService: stub, defaults: defaults)
        dispatcher.attach(to: monitoring, discovery: nil)

        monitoring.startMonitoring()
        await waitUntil { monitoring.latestResults[target.id] != nil }
        await monitoring.stopMonitoringAndWait()

        #expect(target.host == "192.168.77.41", "The target followed the NAS")
        #expect(monitoring.latestResults[target.id]?.isReachable == true)
        #expect(target.measurements.map(\.isReachable) == [true], "The failed check of .40 isn't in the NAS's history")
        #expect(poster.requests.isEmpty, "No target-down alert for the address the NAS left")
    }

    /// At the office a printer has the home NAS's private address. The NAS's turned-off target is
    /// not the printer's: the draft adds a new target and leaves the NAS's link alone.
    @Test func aTurnedOffTargetLinkedToAnotherDeviceIsNotReused() async throws {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let container = try makeContainer()
        let context = container.mainContext
        let homeNAS = UUID()
        let existing = NetworkTarget(name: "Home NAS", host: "192.168.77.40", targetProtocol: .icmp, checkInterval: 120, isEnabled: false)
        context.insert(existing)
        try context.save()
        store.link(target: existing.id, to: homeNAS)
        let device = nas()
        let model = viewModel()
        model.text = nasSentence

        await model.submit(devices: [device], targets: [existing], isScanning: false, linkedDevice: store.device(forTarget:))
        #expect(!model.reusesDisabledTarget)
        model.confirm(store: store, context: context, session: nil)

        let targets = try context.fetch(FetchDescriptor<NetworkTarget>())
        #expect(targets.count == 2, "A target of its own")
        #expect(!existing.isEnabled)
        #expect(store.device(forTarget: existing.id) == homeNAS, "The other device's link is kept")
        let added = try #require(targets.first { $0.id != existing.id })
        #expect(store.device(forTarget: added.id) == device.id)
    }

    /// An enabled target linked to another device doesn't monitor this one, so the draft still
    /// offers a target; one linked to this device counts wherever it points.
    @Test func anEnabledTargetCountsOnlyForTheDeviceItIsLinkedTo() async {
        let device = nas()
        let other = NetworkTarget(name: "Home NAS", host: "192.168.77.40", targetProtocol: .icmp, checkInterval: 120)
        let model = viewModel()
        model.text = nasSentence

        await model.submit(devices: [device], targets: [other], isScanning: false) { _ in UUID() }
        #expect(model.draft?.hasTarget == false)
        #expect(model.addsTarget)

        let own = NetworkTarget(name: "NAS", host: "192.168.77.41", targetProtocol: .icmp, checkInterval: 120)
        model.text = nasSentence
        await model.submit(devices: [device], targets: [own], isScanning: false) { _ in device.id }
        #expect(model.draft?.hasTarget == true)
    }

    @Test func movingATargetPointsItsChecksAtTheNewAddress() async throws {
        let container = try makeContainer()
        let context = container.mainContext
        let target = NetworkTarget(name: "NAS", host: "192.168.77.40", targetProtocol: .icmp, checkInterval: 60)
        context.insert(target)
        try context.save()
        let monitoring = session(context)
        monitoring.startMonitoring()
        await waitUntil { monitoring.latestResults[target.id] != nil }

        monitoring.moveTarget(target.id, to: "192.168.77.41")

        #expect(target.host == "192.168.77.41")
        await waitUntil { monitoring.latestResults[target.id] != nil }
        #expect(monitoring.latestResults[target.id] != nil, "Checked again at the new address")
        await monitoring.stopMonitoringAndWait()
    }

    /// Both paths together: the target times the outage, so the scan's later report of the same
    /// outage doesn't alert a second time.
    @Test func aTargetAndAScanReportingOneOutageAlertOnce() {
        let (defaults, suite) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        store.add(AlertRule(name: "NAS offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: device.id),
                            minimumDuration: 300))
        let target = UUID()
        store.link(target: target, to: device.id)
        let poster = PlainRulePoster()
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults) {
            ([device], nil)
        }
        alerts.handle(targetResult: TargetCheckOutcome(
            targetID: target, name: "NAS", host: "192.168.77.40", isReachable: false, latency: nil, wentDown: true, cameUp: false
        ))
        let known = KnownDevice(macAddress: "02:00:00:77:00:40", ipAddress: "192.168.77.40", name: "uitest-nas",
                                firstSeen: Date().addingTimeInterval(-86400), lastSeen: Date().addingTimeInterval(-900))
        alerts.handle(deviceChanges: [.wentOffline(known)], devices: [device], networkID: nil)
        #expect(poster.requests.isEmpty, "The scan's report is the outage the target is timing")

        alerts.monitoringStopped()
        alerts.handle(deviceChanges: [.wentOffline(known)], devices: [device], networkID: nil)
        #expect(poster.requests.map(\.content.title) == ["NAS offline"], "With monitoring stopped, scans time it again")
    }

    @Test func theEditorWarnsWhenScansCantTimeAnOfflineDuration() {
        let long = AlertRule(name: "Down", trigger: .wentOffline, minimumDuration: 3600)
        #expect(RuleDescription.durationWarning(long, trigger: true, hasTarget: false)
            == "Scans report a device offline once, after 3 missed scans and 15 minutes, so they can't time 1 hour. "
            + "Add a monitoring target for this device.")
        #expect(RuleDescription.durationWarning(long, trigger: true, hasTarget: true) == nil)
        let short = AlertRule(name: "Down", trigger: .wentOffline, minimumDuration: 600)
        #expect(RuleDescription.durationWarning(short, trigger: true, hasTarget: false) == nil)
    }
}
