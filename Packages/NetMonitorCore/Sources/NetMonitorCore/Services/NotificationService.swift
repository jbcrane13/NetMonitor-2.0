import Foundation
import UserNotifications
import os

/// Manages local notifications for network events.
/// Uses UserNotifications framework, which is cross-platform (iOS + macOS 11+).
@MainActor
public final class NotificationService {
    nonisolated private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor",
        category: "NotificationService"
    )

    // MARK: - UserDefaults keys (mirrors AppSettings.Keys)
    private enum Keys {
        static let targetDownAlertEnabled  = "targetDownAlertEnabled"
        static let highLatencyAlertEnabled = "highLatencyAlertEnabled"
        static let highLatencyThreshold    = "highLatencyThreshold"
        static let newDeviceAlertEnabled   = "newDeviceAlertEnabled"
    }

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard

    public init() {}

    // MARK: - Categories

    public static let targetDownCategory  = "TARGET_DOWN"
    public static let highLatencyCategory = "HIGH_LATENCY"
    public static let newDeviceCategory   = "NEW_DEVICE"

    // MARK: - Authorization

    public func requestAuthorization() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                registerCategories()
            }
            return granted
        } catch {
            Self.logger.error("Notification authorization failed: \(error)")
            return false
        }
    }

    public var isAuthorized: Bool {
        get async {
            let settings = await center.notificationSettings()
            return settings.authorizationStatus == .authorized
        }
    }

    private func registerCategories() {
        let dismissAction = UNNotificationAction(
            identifier: "DISMISS",
            title: "Dismiss",
            options: .destructive
        )

        let viewAction = UNNotificationAction(
            identifier: "VIEW",
            title: "View Details",
            options: .foreground
        )

        let targetDownCategory = UNNotificationCategory(
            identifier: Self.targetDownCategory,
            actions: [viewAction, dismissAction],
            intentIdentifiers: []
        )

        let highLatencyCategory = UNNotificationCategory(
            identifier: Self.highLatencyCategory,
            actions: [viewAction, dismissAction],
            intentIdentifiers: []
        )

        let newDeviceCategory = UNNotificationCategory(
            identifier: Self.newDeviceCategory,
            actions: [viewAction, dismissAction],
            intentIdentifiers: []
        )

        center.setNotificationCategories([
            targetDownCategory,
            highLatencyCategory,
            newDeviceCategory
        ])
    }

    // MARK: - Target Down Alert

    public func notifyTargetDown(name: String, host: String) {
        guard defaults.bool(forKey: Keys.targetDownAlertEnabled) != false else { return }

        let content = UNMutableNotificationContent()
        content.title = "Target Down"
        content.body = "\(name) (\(host)) is not responding"
        content.sound = .default
        content.categoryIdentifier = Self.targetDownCategory
        content.userInfo = ["host": host, "name": name]

        let request = UNNotificationRequest(
            identifier: "target-down-\(host)",
            content: content,
            trigger: nil // Deliver immediately
        )

        center.add(request) { error in
            if let error { Self.logger.error("Failed to schedule target down notification: \(error)") }
        }
    }

    // MARK: - High Latency Alert

    public func notifyHighLatency(host: String, latency: Double) {
        guard defaults.object(forKey: Keys.highLatencyAlertEnabled) as? Bool ?? false else { return }

        let threshold = defaults.integer(forKey: Keys.highLatencyThreshold)
        let effectiveThreshold = threshold > 0 ? threshold : 100

        guard latency > Double(effectiveThreshold) else { return }

        let content = UNMutableNotificationContent()
        content.title = "High Latency Detected"
        content.body = String(format: "%@ latency is %.0f ms (threshold: %d ms)", host, latency, effectiveThreshold)
        content.sound = .default
        content.categoryIdentifier = Self.highLatencyCategory
        content.userInfo = ["host": host, "latency": latency]

        let request = UNNotificationRequest(
            identifier: "high-latency-\(host)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error { Self.logger.error("Failed to schedule high latency notification: \(error)") }
        }
    }

    // MARK: - New Device Alert

    public func notifyNewDevice(ipAddress: String, hostname: String?) {
        guard defaults.bool(forKey: Keys.newDeviceAlertEnabled) != false else { return }

        let content = UNMutableNotificationContent()
        content.title = "New Device Detected"
        if let hostname {
            content.body = "\(hostname) (\(ipAddress)) joined the network"
        } else {
            content.body = "\(ipAddress) joined the network"
        }
        content.sound = .default
        content.categoryIdentifier = Self.newDeviceCategory
        content.userInfo = ["ipAddress": ipAddress]

        let request = UNNotificationRequest(
            identifier: "new-device-\(ipAddress)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )

        center.add(request) { error in
            if let error { Self.logger.error("Failed to schedule new device notification: \(error)") }
        }
    }

    // MARK: - Pending Notifications

    public func removeAllPending() {
        center.removeAllPendingNotificationRequests()
    }

    public func removeAllDelivered() {
        center.removeAllDeliveredNotifications()
    }
}
