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
        // The current network, so the devices are saved and listed under its ID (#582).
        let (service, network) = await MainActor.run { (DeviceDiscoveryService.shared, CurrentNetwork.detected()) }
        await service.scanNetwork(profile: network)
        let count = await MainActor.run { service.discoveredDevices.count }

        let dialog: IntentDialog = count == 1
            ? "Found 1 device on your network."
            : "Found \(count) devices on your network."
        return .result(value: count, dialog: dialog)
    }
}
