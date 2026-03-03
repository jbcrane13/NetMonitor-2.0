import AppIntents
import NetMonitorCore

/// Siri/Shortcuts intent: get current network connection status and health info.
struct NetworkStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Network Status"
    // periphery:ignore
    static let description = IntentDescription(
        "Get the current network connection status and connection type.",
        categoryName: "Network Tools"
    )

    func perform() async throws -> some IntentResult {
        return .result()
    }
}
