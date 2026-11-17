import Foundation
@preconcurrency import UserNotifications

/// Shows NetMonitor's alerts while the app is in the foreground. Without a delegate, macOS
/// drops notifications posted by the frontmost app (#403).
final class MacNotificationPresenter: NSObject, UNUserNotificationCenterDelegate, Sendable {
    static let foregroundOptions: UNNotificationPresentationOptions = [.banner, .sound, .list]

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundOptions
    }
}
