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

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = await MainActor.run { NetworkMonitorService() }
        // NWPathMonitor seeds currentPath synchronously, but the first async
        // callback may carry a more accurate view. Brief wait improves accuracy
        // without noticeably slowing the intent.
        try? await Task.sleep(for: .milliseconds(200))
        let (connected, status) = await MainActor.run {
            (service.isConnected, service.statusText)
        }

        let dialog: IntentDialog = connected
            ? "You're connected via \(status)."
            : "No network connection detected."
        return .result(dialog: dialog)
    }
}
