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
    @Test("Target alerts open the local dashboard; device and rule alerts open the device", arguments: [
        ("TARGET_DOWN", ["host": "192.0.2.1"], NotificationRoute.localNetwork),
        ("TARGET_RECOVERED", ["host": "192.0.2.1"], .localNetwork),
        ("HIGH_LATENCY", ["host": "192.0.2.1"], .localNetwork),
        ("NEW_DEVICE", ["ipAddress": "192.0.2.9"], .device(ipAddress: "192.0.2.9")),
        ("RULE_MATCH", ["ipAddress": "192.0.2.10"], .device(ipAddress: "192.0.2.10")),
        ("RULE_MATCH", [:], .localNetwork)
    ])
    func routes(category: String, userInfo: [String: String], expected: NotificationRoute) {
        #expect(NotificationRoute.route(category: category, userInfo: userInfo) == expected)
    }

    @Test("An unknown category goes nowhere")
    func unknownCategory() {
        #expect(NotificationRoute.route(category: "SOMETHING_ELSE", userInfo: [:]) == nil)
    }

    @Test("A device route selects the saved device; an unsaved one falls back to the local dashboard")
    func selection() {
        let local = UUID()
        let printer = LocalDevice(ipAddress: "192.0.2.9", macAddress: "")
        let found = NotificationRouter.selection(for: .device(ipAddress: "192.0.2.9"), devices: [printer], localNetworkID: local)
        #expect(found.section == .section(.devices))
        #expect(found.device == printer.id)

        let missing = NotificationRouter.selection(for: .device(ipAddress: "192.0.2.50"), devices: [printer], localNetworkID: local)
        #expect(missing.section == .network(local))
        #expect(missing.device == nil)

        #expect(NotificationRouter.selection(for: .localNetwork, devices: [], localNetworkID: local).section == .network(local))
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
