import StoreKit
import AppKit

/// Handles "Rate in App Store" functionality for macOS.
/// - Uses SKStoreReviewController for the native in-app rating prompt.
/// - Falls back to opening App Store review page for explicit "Write a Review" action.
enum RateAppService {

    // MARK: - App Store ID

    /// TODO: Update with real App Store ID once live
    static let appStoreID: String = "APP_STORE_ID_PLACEHOLDER"
    private static let reviewURL = "macappstore://itunes.apple.com/app/id\(appStoreID)?action=write-review"
    private static let ratingsURL = "macappstore://itunes.apple.com/app/id\(appStoreID)"

    // MARK: - Smart Rate Prompt

    /// Request in-app rating. Apple may or may not show the prompt
    /// (respects user settings and system limits). Safe to call every time.
    @MainActor
    static func requestReview() {
        SKStoreReviewController.requestReview()
    }

    /// Opens the Mac App Store directly to the review page for this app.
    /// Use this as the explicit "Write a Review" action.
    static func openReviewPage() {
        if let url = URL(string: reviewURL) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Opens the Mac App Store ratings tab for this app.
    static func openAppStorePage() {
        if let url = URL(string: ratingsURL) {
            NSWorkspace.shared.open(url)
        }
    }
}
