import Foundation
@preconcurrency import UserNotifications
import os

/// Hands a notification request to the system. `UNUserNotificationCenter` is the production
/// poster; tests pass a fake that records requests (#403).
@MainActor
public protocol NotificationRequestPosting: AnyObject {
    func post(_ request: UNNotificationRequest)
}

extension UNUserNotificationCenter: NotificationRequestPosting {
    public func post(_ request: UNNotificationRequest) {
        add(request) { error in
            if let error {
                Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "NotificationService")
                    .error("Failed to schedule notification: \(error)")
            }
        }
    }
}

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

    /// The system center, used only for authorization, categories and clearing; it is looked
    /// up when needed so an instance built with a fake poster never touches it.
    private var center: UNUserNotificationCenter { .current() }
    private let poster: any NotificationRequestPosting
    private let defaults: UserDefaults

    /// UserDefaults keys for the new-device and target-down alert toggles.
    public static let targetDownAlertKey = Keys.targetDownAlertEnabled
    public static let newDeviceAlertKey = Keys.newDeviceAlertEnabled
    /// The Mac's "Notify when target recovers" toggle (#445); unset means on.
    public static let targetRecoveryAlertKey = "netmonitor.notifications.targetRecovery"

    public init() {
        poster = UNUserNotificationCenter.current()
        defaults = .standard
    }

    /// Posts through `poster` and reads alert settings from `defaults` (tests, #403).
    public init(poster: any NotificationRequestPosting, defaults: UserDefaults) {
        self.poster = poster
        self.defaults = defaults
    }

    // MARK: - Alert preferences

    /// Target-down alerts are on until the user turns them off; an unset key means on (#391).
    nonisolated static func isTargetDownAlertEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Keys.targetDownAlertEnabled) as? Bool ?? true
    }

    /// New-device alerts are on until the user turns them off; an unset key means on (#391).
    nonisolated static func isNewDeviceAlertEnabled(in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: Keys.newDeviceAlertEnabled) as? Bool ?? true
    }

    // MARK: - Categories

    public static let targetDownCategory  = "TARGET_DOWN"
    public static let targetRecoveredCategory = "TARGET_RECOVERED"
    public static let highLatencyCategory = "HIGH_LATENCY"
    public static let newDeviceCategory   = "NEW_DEVICE"
    public static let ruleMatchCategory   = "RULE_MATCH"

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

        center.setNotificationCategories(Set(Self.categoryIdentifiers.map {
            UNNotificationCategory(identifier: $0, actions: [viewAction, dismissAction], intentIdentifiers: [])
        }))
    }

    /// Every category this service posts, each registered with View and Dismiss actions.
    /// Rule alerts were missing before #445.
    public static let categoryIdentifiers = [
        targetDownCategory, targetRecoveredCategory, highLatencyCategory, newDeviceCategory, ruleMatchCategory
    ]

    // MARK: - Target Down Alert

    public func notifyTargetDown(name: String, host: String) {
        guard Self.isTargetDownAlertEnabled(in: defaults) else { return }

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

        poster.post(request)
    }

    // MARK: - Target Recovered Alert

    /// A monitored target answers again after being down (#445).
    public func notifyTargetRecovered(name: String, host: String) {
        guard defaults.object(forKey: Self.targetRecoveryAlertKey) as? Bool ?? true else { return }
        let content = UNMutableNotificationContent()
        content.title = "Target Recovered"
        content.body = "\(name) (\(host)) is responding again"
        content.sound = .default
        content.categoryIdentifier = Self.targetRecoveredCategory
        content.userInfo = ["host": host, "name": name]
        poster.post(UNNotificationRequest(identifier: "target-recovered-\(host)", content: content, trigger: nil))
    }

    /// A monitored target's latency rose above the Mac's threshold (#445). The caller decides
    /// when it crossed; this posts unconditionally.
    public func notifyTargetLatency(name: String, host: String, latency: Double, thresholdMs: Int) {
        let content = UNMutableNotificationContent()
        content.title = "High Latency Detected"
        content.body = String(format: "%@ (%@) latency is %.0f ms (threshold: %d ms)", name, host, latency, thresholdMs)
        content.sound = .default
        content.categoryIdentifier = Self.highLatencyCategory
        content.userInfo = ["host": host, "latency": latency]
        poster.post(UNNotificationRequest(identifier: "high-latency-\(host)", content: content, trigger: nil))
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

        poster.post(request)
    }

    // MARK: - New Device Alert

    public func notifyNewDevice(ipAddress: String, hostname: String?) {
        guard Self.isNewDeviceAlertEnabled(in: defaults) else { return }

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

        poster.post(request)
    }

    // MARK: - Rule Alert

    /// Posts a user rule's notification (#394). Rules have their own on/off switch, so the
    /// per-alert toggles don't apply.
    public func notifyRuleMatched(ruleName: String, detail: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = ruleName
        content.body = detail
        content.sound = .default
        content.categoryIdentifier = Self.ruleMatchCategory

        let request = UNNotificationRequest(
            identifier: "rule-\(identifier)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        poster.post(request)
    }

    // MARK: - Pending Notifications

    public func removeAllPending() {
        center.removeAllPendingNotificationRequests()
    }

    public func removeAllDelivered() {
        center.removeAllDeliveredNotifications()
    }
}
