import Foundation
import NetMonitorCore
@preconcurrency import UserNotifications

/// Shows NetMonitor's alerts while the app is in the foreground (without a delegate, macOS
/// drops notifications posted by the frontmost app, #403), and opens what an alert is about
/// when the user chooses View Details or clicks it (#478).
final class MacNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let foregroundOptions: UNNotificationPresentationOptions = [.banner, .sound, .list]

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundOptions
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard [NotificationService.viewActionIdentifier, UNNotificationDefaultActionIdentifier].contains(response.actionIdentifier)
        else { return }
        let content = response.notification.request.content
        guard let route = NotificationRoute.route(category: content.categoryIdentifier, userInfo: content.userInfo) else { return }
        await MainActor.run { NotificationRouter.shared.open(route) }
    }
}
