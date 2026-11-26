import AppIntents
import NetMonitorCore
import NetworkScanKit
import SwiftData

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
        let count = await MainActor.run {
            Self.deviceCount(service.discoveredDevices, grouped: AppModelStore.sharedContainer().map(Self.groupedRows) ?? [])
        }

        let dialog: IntentDialog = count == 1
            ? "Found 1 device on your network."
            : "Found \(count) devices on your network."
        return .result(value: count, dialog: dialog)
    }

    /// The devices a scan found, a saved device answering on several interfaces once (#594).
    static func deviceCount(_ scan: [DiscoveredDevice], grouped: [LocalDevice]) -> Int {
        ScanDeviceGroups.onePerDevice(scan, grouped: grouped).count
    }

    @MainActor
    private static func groupedRows(in container: ModelContainer) -> [LocalDevice] {
        (try? ModelContext(container).fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.deviceGroupID != nil }))) ?? []
    }
}
