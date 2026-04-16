import Foundation

/// Routes incoming URLs to the appropriate feature.
///
/// Handles file URLs (.netmonsurvey / .netmonblueprint) opened from the Files
/// app or share sheet. The old `netmonitor://wifi-result` URL scheme callback
/// has been removed — Wi-Fi readings are now delivered in-process via
/// ``SaveWiFiReadingIntent`` and ``WiFiReadingBridge``.
@MainActor
@Observable
final class DeepLinkRouter {

    /// URL of a .netmonsurvey or .netmonblueprint file to open.
    var pendingSurveyFileURL: URL?

    func handle(url: URL) {
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
