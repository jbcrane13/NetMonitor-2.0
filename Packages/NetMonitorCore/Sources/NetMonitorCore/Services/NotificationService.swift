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

    /// Whether each alert would be sent, so a caller words a body only for alerts that go out (#453).
    public var isTargetDownAlertEnabled: Bool { Self.isTargetDownAlertEnabled(in: defaults) }
    public var isNewDeviceAlertEnabled: Bool { Self.isNewDeviceAlertEnabled(in: defaults) }
    public var isTargetRecoveryAlertEnabled: Bool { defaults.object(forKey: Self.targetRecoveryAlertKey) as? Bool ?? true }

    /// The threshold `notifyHighLatency` alerts above, or nil when that alert is off.
    public var highLatencyAlertThreshold: Int? {
        guard defaults.object(forKey: Keys.highLatencyAlertEnabled) as? Bool ?? false else { return nil }
        let threshold = defaults.integer(forKey: Keys.highLatencyThreshold)
        return threshold > 0 ? threshold : 100
    }

    // MARK: - Generated text

    /// The subtitle on an alert whose body the on-device model wrote (#453). The title stays
    /// the app's own text.
    nonisolated public static let generatedSubtitle = "Written on device"

    /// Uses `generatedBody` instead of the fixed body, when there is one, and marks it.
    private static func apply(_ generatedBody: String?, to content: UNMutableNotificationContent) {
        guard let generatedBody else { return }
        content.body = generatedBody
        content.subtitle = generatedSubtitle
    }

    // MARK: - Categories

    nonisolated public static let targetDownCategory  = "TARGET_DOWN"
    nonisolated public static let targetRecoveredCategory = "TARGET_RECOVERED"
    nonisolated public static let highLatencyCategory = "HIGH_LATENCY"
    nonisolated public static let newDeviceCategory   = "NEW_DEVICE"
    nonisolated public static let ruleMatchCategory   = "RULE_MATCH"

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
            identifier: Self.viewActionIdentifier,
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

        center.setNotificationCategories(Set(Self.categoryIdentifiers.map { identifier in
            let actions = Self.categoriesWithViewAction.contains(identifier) ? [viewAction, dismissAction] : [dismissAction]
            return UNNotificationCategory(identifier: identifier, actions: actions, intentIdentifiers: [])
        }))
    }

    /// Every category this service posts. Rule alerts were missing before #445.
    nonisolated public static let categoryIdentifiers = [
        targetDownCategory, targetRecoveredCategory, highLatencyCategory, newDeviceCategory, ruleMatchCategory
    ]

    /// Every category offers View Details; the Mac opens what the alert is about (#478).
    nonisolated public static let categoriesWithViewAction = Set(categoryIdentifiers)

    nonisolated public static let viewActionIdentifier = "VIEW"

    // MARK: - Target Down Alert

    /// `generatedBody` replaces the fixed body when the model wrote one (#453).
    public func notifyTargetDown(name: String, host: String, generatedBody: String? = nil) {
        guard Self.isTargetDownAlertEnabled(in: defaults) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Target Down"
        content.body = "\(name) (\(host)) is not responding"
        Self.apply(generatedBody, to: content)
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
    public func notifyTargetRecovered(name: String, host: String, generatedBody: String? = nil) {
        guard isTargetRecoveryAlertEnabled else { return }
        let content = UNMutableNotificationContent()
        content.title = "Target Recovered"
        content.body = "\(name) (\(host)) is responding again"
        Self.apply(generatedBody, to: content)
        content.sound = .default
        content.categoryIdentifier = Self.targetRecoveredCategory
        content.userInfo = ["host": host, "name": name]
        poster.post(UNNotificationRequest(identifier: "target-recovered-\(host)", content: content, trigger: nil))
    }

    /// A monitored target's latency rose above the Mac's threshold (#445). The caller decides
    /// when it crossed; this posts unconditionally.
    public func notifyTargetLatency(name: String, host: String, latency: Double, thresholdMs: Int, generatedBody: String? = nil) {
        let content = UNMutableNotificationContent()
        content.title = "High Latency Detected"
        content.body = String(format: "%@ (%@) latency is %.0f ms (threshold: %d ms)", name, host, latency, thresholdMs)
        Self.apply(generatedBody, to: content)
        content.sound = .default
        content.categoryIdentifier = Self.highLatencyCategory
        content.userInfo = ["host": host, "latency": latency]
        poster.post(UNNotificationRequest(identifier: "high-latency-\(host)", content: content, trigger: nil))
    }

    // MARK: - High Latency Alert

    public func notifyHighLatency(host: String, latency: Double, generatedBody: String? = nil) {
        guard let effectiveThreshold = highLatencyAlertThreshold, latency > Double(effectiveThreshold) else { return }

        let content = UNMutableNotificationContent()
        content.title = "High Latency Detected"
        content.body = String(format: "%@ latency is %.0f ms (threshold: %d ms)", host, latency, effectiveThreshold)
        Self.apply(generatedBody, to: content)
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

    /// `networkID` is the network the device joined, for View Details (#478).
    public func notifyNewDevice(ipAddress: String, hostname: String?, networkID: UUID? = nil, generatedBody: String? = nil) {
        guard Self.isNewDeviceAlertEnabled(in: defaults) else { return }

        let content = UNMutableNotificationContent()
        content.title = "New Device Detected"
        if let hostname {
            content.body = "\(hostname) (\(ipAddress)) joined the network"
        } else {
            content.body = "\(ipAddress) joined the network"
        }
        Self.apply(generatedBody, to: content)
        content.sound = .default
        content.categoryIdentifier = Self.newDeviceCategory
        content.userInfo = Self.deviceUserInfo(ipAddress: ipAddress, networkID: networkID)

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
    /// `ipAddress` and `networkID` are the device or target the rule matched, for View Details (#478).
    public func notifyRuleMatched(
        ruleName: String, detail: String, identifier: String, ipAddress: String? = nil, networkID: UUID? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = ruleName
        content.body = detail
        content.sound = .default
        content.categoryIdentifier = Self.ruleMatchCategory
        if let ipAddress {
            content.userInfo = Self.deviceUserInfo(ipAddress: ipAddress, networkID: networkID)
        }

        let request = UNNotificationRequest(
            identifier: "rule-\(identifier)-\(Date().timeIntervalSince1970)",
            content: content,
            trigger: nil
        )
        poster.post(request)
    }

    /// The payload View Details routes on: the device's address and its network.
    nonisolated static func deviceUserInfo(ipAddress: String, networkID: UUID?) -> [String: String] {
        var info = ["ipAddress": ipAddress]
        info["networkID"] = networkID?.uuidString
        return info
    }

    // MARK: - Pending Notifications

    public func removeAllPending() {
        center.removeAllPendingNotificationRequests()
    }

    public func removeAllDelivered() {
        center.removeAllDeliveredNotifications()
    }
}
