import NetMonitorCore
import StoreKit
import SwiftUI

/// Handles "Rate in App Store" functionality.
/// - Uses SKStoreReviewController for the native in-app rating prompt (no UI needed).
/// - Falls back to opening App Store review page for "Write a Review" action.
@MainActor enum RateAppService {

    // MARK: - App Store ID

    /// App Store Connect app ID for com.blakemiller.netmonitor (NetMonitor).
    static let appStoreID: String = "6759060947"
    private static let reviewURL = "itms-apps://itunes.apple.com/app/id\(appStoreID)?action=write-review"
    private static let ratingsURL = "itms-apps://itunes.apple.com/app/id\(appStoreID)"

    // MARK: - Smart Rate Prompt

    /// Request in-app rating. Apple may or may not show the prompt
    /// (respects user settings and system limits). Safe to call every time.
    /// Returns `false` when there is no foreground scene to show it in.
    @discardableResult
    static func requestReview() -> Bool {
        if let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: scene)
            return true
        }
        return false
    }

    /// Asks for a review automatically after meaningful use (#337).
    static let reviewPrompt = ReviewPromptPolicy { requestReview() }

    /// Opens the App Store directly to the review page for this app.
    /// Use this as the explicit "Write a Review" action.
    static func openReviewPage() {
        if let url = URL(string: reviewURL) {
            UIApplication.shared.open(url)
        }
    }

    /// Opens the App Store ratings tab for this app.
    static func openAppStorePage() {
        if let url = URL(string: ratingsURL) {
            UIApplication.shared.open(url)
        }
    }
}
