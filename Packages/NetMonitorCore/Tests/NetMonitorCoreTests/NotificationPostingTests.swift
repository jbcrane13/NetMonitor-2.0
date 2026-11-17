import Foundation
import Testing
@preconcurrency import UserNotifications
@testable import NetMonitorCore

@MainActor
private final class FakeNotificationPoster: NotificationRequestPosting {
    private(set) var requests: [UNNotificationRequest] = []
    func post(_ request: UNNotificationRequest) { requests.append(request) }
}

/// Alerts post through the injected poster and honor each toggle (#403).
@Suite("NotificationService posting")
@MainActor
struct NotificationPostingTests {
    private func makeService() -> (NotificationService, FakeNotificationPoster, UserDefaults, String) {
        let suite = "NotificationPostingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let poster = FakeNotificationPoster()
        return (NotificationService(poster: poster, defaults: defaults), poster, defaults, suite)
    }

    @Test func freshInstallPostsTargetDownAndNewDeviceAlerts() {
        let (service, poster, defaults, suite) = makeService()
        defer { defaults.removePersistentDomain(forName: suite) }

        service.notifyTargetDown(name: "Router", host: "192.168.1.1")
        service.notifyNewDevice(ipAddress: "192.168.1.50", hostname: "phone")

        #expect(poster.requests.map(\.content.categoryIdentifier) == [
            NotificationService.targetDownCategory,
            NotificationService.newDeviceCategory
        ])
    }

    @Test func targetDownToggleOffStopsOnlyThatAlert() {
        let (service, poster, defaults, suite) = makeService()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: NotificationService.targetDownAlertKey)

        service.notifyTargetDown(name: "Router", host: "192.168.1.1")
        service.notifyNewDevice(ipAddress: "192.168.1.50", hostname: nil)

        #expect(poster.requests.map(\.content.categoryIdentifier) == [NotificationService.newDeviceCategory])
    }

    @Test func newDeviceToggleOffStopsOnlyThatAlert() {
        let (service, poster, defaults, suite) = makeService()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(false, forKey: NotificationService.newDeviceAlertKey)

        service.notifyTargetDown(name: "Router", host: "192.168.1.1")
        service.notifyNewDevice(ipAddress: "192.168.1.50", hostname: nil)

        #expect(poster.requests.map(\.content.categoryIdentifier) == [NotificationService.targetDownCategory])
    }
}
