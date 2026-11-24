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
        #expect(saved.first?.conditions == AlertRuleConditions(device: "uitest-nas", deviceID: device.id))
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
        let rule = AlertRule(name: "Offline", trigger: .wentOffline, conditions: AlertRuleConditions(device: "uitest-nas", deviceID: device.id),
                             minimumDuration: 300)
        device.customName = "Basement NAS"
        #expect(RuleDescription.summary(rule, networks: [], devices: [device]) == "Goes offline · for 5 minutes · device Basement NAS")
        #expect(RuleDescription.summary(rule, networks: [], devices: []) == "Goes offline · for 5 minutes · device a removed device")
    }
}
