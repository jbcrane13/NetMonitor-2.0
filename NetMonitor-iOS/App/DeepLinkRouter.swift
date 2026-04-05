import Foundation

/// Routes incoming URLs to the appropriate feature.
///
/// Handles two URL types:
/// - `netmonitor://wifi-result` — Shortcuts Wi-Fi callback (ShortcutsWiFiProvider)
/// - File URLs (.netmonsurvey / .netmonblueprint) — opens in heatmap survey view
@MainActor
@Observable
final class DeepLinkRouter {

    /// URL of a .netmonsurvey or .netmonblueprint file to open.
    var pendingSurveyFileURL: URL?

    /// Whether a Shortcuts Wi-Fi callback was received.
    var wifiCallbackReceived: Bool = false

    func handle(url: URL) {
        // URL scheme callback from Shortcuts
        if url.scheme == "netmonitor", url.host == "wifi-result" {
            wifiCallbackReceived = true
            // The ShortcutsWiFiProvider handles the actual data read via handleURLCallback()
            // Notify it through a notification so any active provider instance picks it up.
            NotificationCenter.default.post(name: .shortcutsWiFiCallbackReceived, object: nil)
            return
        }

        // File URL opened from Files app or share sheet
        if url.isFileURL {
            let ext = url.pathExtension
            if ext == "netmonsurvey" || ext == "netmonblueprint" {
                pendingSurveyFileURL = url
            }
        }
    }

    /// Consumes and returns the pending file URL, clearing it.
    func consumePendingFile() -> URL? {
        let url = pendingSurveyFileURL
        pendingSurveyFileURL = nil
        return url
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let shortcutsWiFiCallbackReceived = Notification.Name("shortcutsWiFiCallbackReceived")
}
