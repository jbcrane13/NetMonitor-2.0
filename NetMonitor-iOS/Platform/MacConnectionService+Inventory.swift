import Foundation
import NetMonitorCore
import SwiftData

// MARK: - The Mac's inventory (#585)

extension MacConnectionService {
    /// The first heartbeat offering the inventory on a link asks for it at once; the Mac then
    /// sends it after each scan.
    func receivedInventoryOffer(_ heartbeat: HeartbeatPayload) {
        guard heartbeat.offersInventory, !macOffersInventory else { return }
        macOffersInventory = true
        Task { await send(command: CommandPayload(action: .refreshDevices)) }
    }

    /// The connected Mac's inventory for `network`, as of `now`: live only over the current link,
    /// from a Mac that offered it, for the same subnet, with a recent scan.
    func inventory(for network: NetworkProfile?, now: Date) -> MacInventory.Availability {
        MacInventory.availability(
            list: lastDeviceList, receivedAt: lastDeviceListReceivedAt, connected: connectionState.isConnected,
            offersInventory: macOffersInventory, subnet: network?.subnetCIDR, now: now
        )
    }

    /// The Mac's record of `device`, matched among the saved devices of its network as the list
    /// matches them, so detail and the list agree (#585).
    func macRecord(of device: DeviceProjection, in context: ModelContext, now: Date) -> MacInventory.Record? {
        let networkID = device.primary.networkProfileID
        guard case .live(let inventory) = inventory(for: profile(for: networkID), now: now) else { return nil }
        let rows = SavedDeviceList.recentRows(network: networkID, in: context)
        return inventory.matches(DeviceGroups.project(rows)).record(for: device)
    }

    /// A saved network's profile; the UI-test network stands for the current one.
    private func profile(for networkID: UUID?) -> NetworkProfile? {
        if UITestFakeDeviceFeed.isEnabled, networkID == UITestBootstrap.networkProfileID {
            return networkProfileManager.activeProfile
        }
        return networkProfileManager.profiles.first { $0.id == networkID }
    }
}
