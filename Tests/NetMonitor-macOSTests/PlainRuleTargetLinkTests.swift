import Foundation
import NetMonitorCore
import SwiftData
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_macOS

@MainActor
private final class ReviewPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

/// The #574 review of described rules: one alert per outage, targets that come and go, links
/// that follow their device and rules (#450).
@Suite("Plain-English rules on the Mac: targets and links (#450, #574)", .serialized)
@MainActor
struct PlainRuleTargetLinkTests {
    private let nasSentence = "Tell me if the NAS is down for more than five minutes"

    /// Never the standard defaults: they hold the user's real rules.
    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "PlainRuleTargetLinkTests.\(UUID().uuidString)"
        return try (#require(UserDefaults(suiteName: suite)), suite)
    }

    private func nas() -> LocalDevice {
        LocalDevice(ipAddress: "192.168.77.40", macAddress: "02:00:00:77:00:40", hostname: "uitest-nas", deviceType: .storage)
    }

    private func viewModel() -> PlainRuleMacViewModel {
        PlainRuleMacViewModel(parser: FixedRuleIntentParser.uiTest, timing: RuleTiming(targetCheckInterval: 30))
    }

    private func alerts(_ store: AlertRuleStore, _ defaults: UserDefaults, _ poster: ReviewPoster, devices: [LocalDevice],
                        active: Set<UUID>? = nil) -> MacRuleAlerts {
        let alerts = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults) {
            (devices, nil)
        }
        if let active {
            alerts.activeTargets = { active }
        }
        return alerts
    }

    private func check(_ alerts: MacRuleAlerts, _ target: UUID, host: String = "192.168.77.40", reachable: Bool, down: Bool = false,
                       up: Bool = false) {
        alerts.handle(targetResult: TargetCheckOutcome(
            targetID: target, name: "NAS", host: host, isReachable: reachable, latency: reachable ? 4 : nil, wentDown: down, cameUp: up
        ))
    }

    private func scanOffline(_ device: LocalDevice) -> DeviceChangeEvent {
        .wentOffline(KnownDevice(macAddress: device.macAddress, ipAddress: device.ipAddress, name: device.hostname,
                                 firstSeen: Date().addingTimeInterval(-86400), lastSeen: Date().addingTimeInterval(-900)))
    }

    /// "Tell me when the NAS goes offline" with the offered target: one notification per outage.
    @Test func aRuleWithoutADurationAlertsOnceWhenATargetAndAScanReportTheOutage() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        store.add(AlertRule(name: "NAS offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: device.id)))
        let target = UUID()
        store.link(target: target, to: device.id)
        let poster = ReviewPoster()
        let rules = alerts(store, defaults, poster, devices: [device], active: [target])

        check(rules, target, reachable: false, down: true)
        rules.handle(deviceChanges: [scanOffline(device)], devices: [device], networkID: nil)

        #expect(poster.requests.map(\.content.title) == ["NAS offline"])
    }

    /// A manual "offline 30 min" rule on storage devices; its target is deleted while monitoring runs.
    @Test func aDeletedTargetNoLongerSilencesAManualRulesScanAlert() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        store.add(AlertRule(name: "Storage down", trigger: .wentOffline, conditions: AlertRuleConditions(deviceType: .storage),
                            minimumDuration: 600))
        let target = UUID()
        var active: Set<UUID> = [target]
        let poster = ReviewPoster()
        let rules = MacRuleAlerts(store: store, service: NotificationService(poster: poster, defaults: defaults), defaults: defaults) {
            ([device], nil)
        }
        rules.activeTargets = { active }
        check(rules, target, reachable: true)
        rules.handle(deviceChanges: [scanOffline(device)], devices: [device], networkID: nil)
        #expect(poster.requests.isEmpty, "The target covers the NAS")

        active = []
        rules.handle(deviceChanges: [scanOffline(device)], devices: [device], networkID: nil)

        #expect(poster.requests.map(\.content.title) == ["Storage down"])
    }

    @Test func aDeletedTargetsResultsAreIgnored() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        store.add(AlertRule(name: "Down", trigger: .wentOffline))
        let poster = ReviewPoster()
        let rules = alerts(store, defaults, poster, devices: [nas()], active: [])
        check(rules, UUID(), reachable: false, down: true)
        #expect(poster.requests.isEmpty)
    }

    /// The NAS goes down; while it's down a phone takes its address and answers the target. The
    /// NAS's outage carries on and its five-minute rule (here 50 ms) still alerts.
    @Test func anOutageStillAlertsWhenAnotherDeviceTakesTheAddress() async throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = nas()
        let phone = LocalDevice(ipAddress: "192.168.77.40", macAddress: "02:00:00:77:00:99", hostname: "phone", deviceType: .phone)
        phone.status = .offline
        store.add(AlertRule(name: "NAS offline", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: device.id),
                            minimumDuration: 0.05))
        let target = UUID()
        store.link(target: target, to: device.id)
        let poster = ReviewPoster()
        let rules = alerts(store, defaults, poster, devices: [device, phone], active: [target])

        check(rules, target, reachable: false, down: true)
        device.status = .offline
        phone.status = .online
        try await Task.sleep(for: .milliseconds(80))
        check(rules, target, reachable: true, up: true)

        #expect(poster.requests.map(\.content.title) == ["NAS offline"])
        #expect(poster.requests.first?.content.body == "uitest-nas went offline")
    }

    @Test func deletingATargetOrTheLastRuleOnItsDeviceRemovesTheLink() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let device = UUID()
        let first = AlertRule(name: "Down", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: device))
        let second = AlertRule(name: "Up", trigger: .cameOnline, conditions: AlertRuleConditions(deviceID: device))
        store.add(first)
        store.add(second)
        let (deleted, kept) = (UUID(), UUID())
        store.link(target: deleted, to: device)
        store.link(target: kept, to: device)

        store.unlink(targets: [deleted])
        #expect(store.device(forTarget: deleted) == nil)
        #expect(store.device(forTarget: kept) == device)

        store.delete(id: first.id)
        #expect(store.device(forTarget: kept) == device, "Another rule still names the device")
        store.delete(id: second.id)
        #expect(store.device(forTarget: kept) == nil, "No rule left on the device: the target stops following it")
    }

    @Test func pruningAtLaunchDropsLinksWhoseTargetDeviceOrRuleIsGone() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AlertRuleStore(defaults: defaults)
        let (device, unnamed, gone) = (UUID(), UUID(), UUID())
        store.add(AlertRule(name: "Down", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: device)))
        store.add(AlertRule(name: "Gone", trigger: .wentOffline, conditions: AlertRuleConditions(deviceID: gone)))
        let (live, deletedTarget, goneDevice, noRule) = (UUID(), UUID(), UUID(), UUID())
        store.link(target: live, to: device)
        store.link(target: deletedTarget, to: device)
        store.link(target: goneDevice, to: gone)
        store.link(target: noRule, to: unnamed)

        store.pruneLinks(targets: [live, goneDevice, noRule], devices: [device, unnamed])

        #expect(AlertRuleStore(defaults: defaults).device(forTarget: live) == device)
        for target in [deletedTarget, goneDevice, noRule] {
            #expect(store.device(forTarget: target) == nil)
        }
    }

    @Test func theEditorAndTheDraftAgreeOnWhichTargetChecksADevice() async throws {
        let device = nas()
        let other = UUID()
        let linkedElsewhere = NetworkTarget(name: "Old", host: device.ipAddress, targetProtocol: .icmp)
        let unlinked = NetworkTarget(name: "NAS", host: device.ipAddress, targetProtocol: .icmp)
        func links(_ id: UUID) -> UUID? { id == linkedElsewhere.id ? other : nil }
        #expect(!PlainRuleMacViewModel.isMonitored(deviceID: device.id, address: device.ipAddress, targets: [linkedElsewhere],
                                                   linkedDevice: links),
                "A target linked to another device doesn't count, even at this address")
        #expect(PlainRuleMacViewModel.isMonitored(deviceID: device.id, address: device.ipAddress, targets: [unlinked],
                                                  linkedDevice: links))
        unlinked.isEnabled = false
        #expect(!PlainRuleMacViewModel.isMonitored(deviceID: device.id, address: device.ipAddress, targets: [unlinked],
                                                   linkedDevice: links))

        let model = viewModel()
        model.text = nasSentence
        await model.submit(devices: [device], targets: [linkedElsewhere], isScanning: false, linkedDevice: links)
        #expect(model.draft?.hasTarget == false, "The draft offers a target, as the editor would warn")
        #expect(model.draft?.offersTarget == true)
    }
}
