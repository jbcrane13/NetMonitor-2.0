import Foundation
import NetMonitorCore
import SwiftData
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_macOS

@MainActor
private final class Poster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

/// #478: View Details opens what an alert is about.
@MainActor
struct NotificationRouteTests {
    @Test("Target alerts open the targets; device and rule alerts open the device", arguments: [
        (NotificationService.targetDownCategory, ["host": "192.0.2.1"], NotificationRoute.targets),
        (NotificationService.targetRecoveredCategory, ["host": "192.0.2.1"], .targets),
        (NotificationService.highLatencyCategory, ["host": "192.0.2.1"], .targets),
        (NotificationService.newDeviceCategory, ["ipAddress": "192.0.2.9"], .device(ipAddress: "192.0.2.9", networkID: nil)),
        (NotificationService.ruleMatchCategory, ["ipAddress": "192.0.2.10"], .device(ipAddress: "192.0.2.10", networkID: nil)),
        (NotificationService.ruleMatchCategory, [:], .targets)
    ])
    func routes(category: String, userInfo: [String: String], expected: NotificationRoute) {
        #expect(NotificationRoute.route(category: category, userInfo: userInfo) == expected)
    }

    @Test("An unknown category goes nowhere")
    func unknownCategory() {
        #expect(NotificationRoute.route(category: "SOMETHING_ELSE", userInfo: [:]) == nil)
    }

    @Test("The identity question's route opens the Devices list (#645)")
    func devicesRoute() {
        let found = NotificationRouter.selection(for: .devices, devices: [], localNetworkID: UUID())
        #expect(found.section == .section(.devices))
        #expect(found.device == nil)
    }

    @Test("A device route selects the device on the alert's network; otherwise the local dashboard")
    func selection() {
        let local = UUID(), home = UUID(), office = UUID()
        let homePrinter = LocalDevice(ipAddress: "192.0.2.9", macAddress: "", networkProfileID: home)
        let officePrinter = LocalDevice(ipAddress: "192.0.2.9", macAddress: "", networkProfileID: office)
        let both = [homePrinter, officePrinter]

        let found = NotificationRouter.selection(for: .device(ipAddress: "192.0.2.9", networkID: office), devices: both, localNetworkID: local)
        #expect(found.section == .section(.devices))
        #expect(found.device == officePrinter.id)

        // Two saved devices share the address and the alert names no network: don't guess.
        let ambiguous = NotificationRouter.selection(for: .device(ipAddress: "192.0.2.9", networkID: nil), devices: both, localNetworkID: local)
        #expect(ambiguous.device == nil)
        #expect(ambiguous.section == .network(local))

        let only = NotificationRouter.selection(for: .device(ipAddress: "192.0.2.9", networkID: nil), devices: [homePrinter], localNetworkID: local)
        #expect(only.device == homePrinter.id)

        let missing = NotificationRouter.selection(for: .device(ipAddress: "192.0.2.50", networkID: home), devices: both, localNetworkID: local)
        #expect(missing.section == .network(local))
        #expect(missing.device == nil)
        #expect(NotificationRouter.selection(for: .targets, devices: [], localNetworkID: local).section == .network(local))
    }

    @Test("A new-device alert carries its network for View Details")
    func payloadCarriesNetwork() {
        let suite = "NotificationRouteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }
        let poster = Poster()
        let network = UUID()
        NotificationService(poster: poster, defaults: defaults ?? .standard)
            .notifyNewDevice(ipAddress: "192.0.2.9", hostname: nil, networkID: network)
        let info = poster.requests.first?.content.userInfo ?? [:]
        #expect(NotificationRoute.route(category: NotificationService.newDeviceCategory, userInfo: info)
            == .device(ipAddress: "192.0.2.9", networkID: network))
    }

    @Test("A rule alert carries the matched address for View Details")
    func ruleAlertCarriesAddress() {
        let suite = "NotificationRouteTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }
        let poster = Poster()
        NotificationService(poster: poster, defaults: defaults ?? .standard)
            .notifyRuleMatched(ruleName: "Printer", detail: "came online", identifier: "r1", ipAddress: "192.0.2.9")
        #expect(poster.requests.first?.content.userInfo["ipAddress"] as? String == "192.0.2.9")
    }
}
