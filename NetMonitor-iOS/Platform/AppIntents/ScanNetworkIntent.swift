import AppIntents
import NetMonitorCore

/// Siri/Shortcuts intent: scan the local network and return device count.
struct ScanNetworkIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan My Network"
    static let description = IntentDescription(
        "Scan the local network and return the number of discovered devices.",
        categoryName: "Network Tools"
    )

    func perform() async throws -> some IntentResult {
        let service = await MainActor.run { DeviceDiscoveryService.shared }

        // scanNetwork(subnet:) is nonisolated async — call from any context
        await service.scanNetwork(subnet: nil)

        return .result()
    }
}
