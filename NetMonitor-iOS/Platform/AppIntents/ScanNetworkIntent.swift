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
        let (service, network, before) = await MainActor.run {
            (DeviceDiscoveryService.shared, CurrentNetwork.detected(), DeviceDiscoveryService.shared.droppedScanCount)
        }
        await service.scanNetwork(profile: network)
        // Dropped because the network path changed while it ran (#628): its list is the old one.
        let dropped = await MainActor.run { service.droppedScanCount != before }
        let count = dropped ? 0 : await MainActor.run {
            Self.deviceCount(service.discoveredDevices, grouped: AppModelStore.sharedContainer().map(Self.groupedRows) ?? [])
        }
        return .result(value: count, dialog: IntentDialog(stringLiteral: Self.message(count: count, dropped: dropped)))
    }

    /// What the intent says: the count, or that a dropped scan saved nothing (#628).
    static func message(count: Int, dropped: Bool) -> String {
        if dropped {
            return "The network changed during the scan, so nothing was saved. Try again."
        }
        return count == 1 ? "Found 1 device on your network." : "Found \(count) devices on your network."
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
