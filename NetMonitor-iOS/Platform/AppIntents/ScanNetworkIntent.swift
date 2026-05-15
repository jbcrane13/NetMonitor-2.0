import AppIntents
import NetMonitorCore

/// Siri/Shortcuts intent: scan the local network and return device count.
struct ScanNetworkIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan My Network"
    // periphery:ignore
    static let description = IntentDescription(
        "Scan the local network and return the number of discovered devices.",
        categoryName: "Network Tools"
    )

    func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let service = await MainActor.run { DeviceDiscoveryService.shared }
        await service.scanNetwork(subnet: nil)
        let count = await MainActor.run { service.discoveredDevices.count }

        let dialog: IntentDialog = count == 1
            ? "Found 1 device on your network."
            : "Found \(count) devices on your network."
        return .result(value: count, dialog: dialog)
    }
}
