import Foundation
import NetMonitorCore
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitor_macOS

@MainActor
private final class RecordingPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    var categories: [String] { requests.map(\.content.categoryIdentifier) }
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

/// #445: the recovery toggle, the latency threshold and the timing defaults do something.
@MainActor
struct TargetAlertSettingsTests {
    private let targetID = UUID()

    private func makeDefaults() -> UserDefaults {
        let suite = "TargetAlertSettingsTests.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite) ?? .standard
    }

    private func check(reachable: Bool = true, latency: Double?, wentDown: Bool = false, cameUp: Bool = false) -> TargetCheckOutcome {
        TargetCheckOutcome(
            targetID: targetID, name: "Router", host: "192.0.2.1",
            isReachable: reachable, latency: latency, wentDown: wentDown, cameUp: cameUp
        )
    }

    @Test("A target that comes back up alerts, unless recovery alerts are off")
    func recovery() {
        let defaults = makeDefaults()
        let poster = RecordingPoster()
        let alerts = MacAlertNotifier(service: NotificationService(poster: poster, defaults: defaults), defaults: defaults)

        alerts.targetChecked(check(latency: 4, cameUp: true))
        #expect(poster.categories == [NotificationService.targetRecoveredCategory])

        defaults.set(false, forKey: NotificationService.targetRecoveryAlertKey)
        alerts.targetChecked(check(latency: 4, cameUp: true))
        #expect(poster.requests.count == 1)
    }

    @Test("Latency above the threshold alerts once per crossing")
    func latencyCrossing() {
        let defaults = makeDefaults()
        defaults.set(200.0, forKey: MacAlertNotifier.latencyThresholdKey)
        let poster = RecordingPoster()
        let alerts = MacAlertNotifier(service: NotificationService(poster: poster, defaults: defaults), defaults: defaults)

        alerts.targetChecked(check(latency: 50))
        alerts.targetChecked(check(latency: 250))
        alerts.targetChecked(check(latency: 300)) // still above: no second alert
        alerts.targetChecked(check(latency: 80))
        alerts.targetChecked(check(latency: 260)) // crossed again
        #expect(poster.categories == [NotificationService.highLatencyCategory, NotificationService.highLatencyCategory])
        #expect(poster.requests.first?.content.body.contains("threshold: 200 ms") == true)
    }

    @Test("The default threshold is 500 ms, and the master switch silences both alerts")
    func defaultsAndMasterSwitch() {
        let defaults = makeDefaults()
        let poster = RecordingPoster()
        let alerts = MacAlertNotifier(service: NotificationService(poster: poster, defaults: defaults), defaults: defaults)
        alerts.targetChecked(check(latency: 450))
        #expect(poster.requests.isEmpty)

        defaults.set(false, forKey: MacAlertNotifier.notificationsEnabledKey)
        alerts.targetChecked(check(latency: 900, cameUp: true))
        #expect(poster.requests.isEmpty)
    }

    @Test("Rule alerts' category is registered with the others")
    func ruleCategoryRegistered() {
        #expect(NotificationService.categoryIdentifiers.contains(NotificationService.ruleMatchCategory))
        #expect(Set(NotificationService.categoryIdentifiers).count == NotificationService.categoryIdentifiers.count)
        // Nothing opens a target or rule from a notification yet, so the new ones offer Dismiss only.
        #expect(!NotificationService.categoriesWithViewAction.contains(NotificationService.ruleMatchCategory))
        #expect(!NotificationService.categoriesWithViewAction.contains(NotificationService.targetRecoveredCategory))
    }

    @Test("New targets start from the Monitoring settings' interval and timeout")
    func targetDefaults() {
        let defaults = makeDefaults()
        #expect(TargetDefaults.interval(in: defaults) == 30)
        #expect(TargetDefaults.timeout(in: defaults) == 5)
        defaults.set(10, forKey: TargetDefaults.intervalKey)
        defaults.set(3, forKey: TargetDefaults.timeoutKey)
        #expect(TargetDefaults.interval(in: defaults) == 10)
        #expect(TargetDefaults.timeout(in: defaults) == 3)
    }
}
