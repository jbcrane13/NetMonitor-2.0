import Foundation

/// Decides when to ask for an App Store review automatically (#337): after
/// ``scanThreshold`` completed scans or ``monitoringThreshold`` of cumulative
/// monitoring, at most once per app version.
///
/// Platforms supply `requestReview`, which returns `false` when the prompt could
/// not be requested (e.g. no foreground window scene); the version is then not
/// marked as prompted, so the next milestone tries again.
@MainActor
public final class ReviewPromptPolicy {

    public static let scanThreshold = 3
    public static let monitoringThreshold: TimeInterval = 10 * 60

    enum Keys {
        static let completedScans = "reviewPrompt_completedScanCount"
        static let monitoringSeconds = "reviewPrompt_totalMonitoringSeconds"
        static let lastPromptedVersion = "reviewPrompt_lastPromptedVersion"
    }

    private let defaults: UserDefaults
    private let appVersion: String
    private let requestReview: @MainActor () -> Bool

    public init(
        defaults: UserDefaults = .standard,
        appVersion: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
        requestReview: @escaping @MainActor () -> Bool
    ) {
        self.defaults = defaults
        self.appVersion = appVersion
        self.requestReview = requestReview
    }

    /// Call when a user-started network scan finishes.
    public func recordScanCompleted() {
        let count = defaults.integer(forKey: Keys.completedScans) + 1
        defaults.set(count, forKey: Keys.completedScans)
        if count >= Self.scanThreshold {
            requestReviewIfEligible()
        }
    }

    /// Call when a monitoring period ends, with its length in seconds.
    public func recordMonitoring(duration: TimeInterval) {
        guard duration > 0 else { return }
        let total = defaults.double(forKey: Keys.monitoringSeconds) + duration
        defaults.set(total, forKey: Keys.monitoringSeconds)
        if total >= Self.monitoringThreshold {
            requestReviewIfEligible()
        }
    }

    private func requestReviewIfEligible() {
        guard defaults.string(forKey: Keys.lastPromptedVersion) != appVersion else { return }
        if requestReview() {
            defaults.set(appVersion, forKey: Keys.lastPromptedVersion)
        }
    }
}
