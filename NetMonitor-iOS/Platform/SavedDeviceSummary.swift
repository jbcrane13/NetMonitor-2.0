import Foundation
import NetMonitorCore
import NetworkScanKit
import Observation
import SwiftData
import WidgetKit

/// The saved devices that answered a network's latest scan, counted as devices (#594): a group of
/// interfaces is one, at its current member's address. The dashboard's device count and the
/// widget's count and top three come from it, published after each scan is reconciled.
struct SavedDeviceSummary: Equatable {
    struct Entry: Equatable {
        let name: String
        let ipAddress: String
    }

    let count: Int
    /// The first three by address.
    let top: [Entry]

    /// - Parameter rows: saved rows, complete groups; those of `network` are counted.
    init(rows: [LocalDevice], network: UUID?, presence: PresenceSnapshot) {
        let answered = DeviceGroups.project(rows.filter { $0.networkProfileID == network })
            .filter { presence.answeredLatestScan($0) }
            .sorted { DeviceList.compareIPAddresses($0.ipAddress, $1.ipAddress) }
        count = answered.count
        top = answered.prefix(3).map { Entry(name: $0.displayName, ipAddress: $0.ipAddress) }
    }

    /// A scan no saved network describes (#594 review): its own devices, in the scan's order (by
    /// address), as the widget showed every scan before #594.
    init(scan: [DiscoveredDevice]) {
        count = scan.count
        top = scan.prefix(3).map { Entry(name: $0.displayName, ipAddress: $0.ipAddress) }
    }

    /// Writes the count and the top three where the widget reads them.
    func publish(to defaults: UserDefaults) {
        let topDevices = top.map { ["name": $0.name, "ip": $0.ipAddress] }
        if let data = try? JSONSerialization.data(withJSONObject: topDevices) {
            defaults.set(data, forKey: AppSettings.Keys.widgetTopDevices)
        }
        defaults.set(count, forKey: AppSettings.Keys.widgetDeviceCount)
    }
}

/// Each network's ``SavedDeviceSummary`` as of its latest reconciled scan (#594). The app refreshes
/// it after every saved scan, which also updates the widget; the dashboard reads its count.
@MainActor
@Observable
final class SavedDeviceSummaryModel {
    static let shared = SavedDeviceSummaryModel()

    private(set) var summaries: [UUID: SavedDeviceSummary] = [:]

    /// The count for `network`, or nil before any of its scans was summarized.
    func count(for network: UUID?) -> Int? {
        network.flatMap { summaries[$0]?.count }
    }

    /// Publishes a saved scan: each network it saved (`networks`), from its saved devices; a scan
    /// that saved no network (none was known) still publishes its own devices to the widget.
    func publish(
        savedScan scan: [DiscoveredDevice], networks: Set<UUID>, in context: ModelContext, presence: PresenceSnapshot,
        defaults: UserDefaults = UserDefaults(suiteName: AppSettings.appGroupSuiteName) ?? .standard,
        reloadWidget: Bool = true
    ) {
        guard !networks.isEmpty else {
            SavedDeviceSummary(scan: scan).publish(to: defaults)
            if reloadWidget {
                WidgetCenter.shared.reloadTimelines(ofKind: "DeviceGlanceWidget")
            }
            return
        }
        for network in networks {
            refresh(network: network, in: context, presence: presence, defaults: defaults, reloadWidget: reloadWidget)
        }
    }

    /// Summarizes `network`'s saved devices from `context`, and publishes it to the widget.
    func refresh(
        network: UUID?, in context: ModelContext, presence: PresenceSnapshot,
        defaults: UserDefaults = UserDefaults(suiteName: AppSettings.appGroupSuiteName) ?? .standard,
        reloadWidget: Bool = true
    ) {
        guard let network else { return }
        let rows = (try? context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == network }))) ?? []
        let summary = SavedDeviceSummary(rows: rows, network: network, presence: presence)
        summaries[network] = summary
        summary.publish(to: defaults)
        if reloadWidget {
            WidgetCenter.shared.reloadTimelines(ofKind: "DeviceGlanceWidget")
        }
    }
}

/// The names of devices with several interfaces, by every member's address (#594), for screens
/// that name a scan's devices by address (Port Forwards). A device of one row
/// keeps the name the scan gives it, as before.
enum GroupedDeviceNames {
    /// - Parameter rows: saved rows, complete groups.
    static func byAddress(_ rows: [LocalDevice]) -> [String: String] {
        DeviceGroups.project(rows).filter(\.isGroup).reduce(into: [:]) { names, device in
            for member in device.members where names[member.ipAddress] == nil {
                names[member.ipAddress] = device.displayName
            }
        }
    }
}

/// A scan's devices with each saved device of several interfaces once (#594), for screens that
/// list the scan itself (the map). A device that matches a grouped row (an identical real MAC,
/// else the same address on the same network) stands for the group; the one at the group's
/// current member's address is kept, else the first.
enum ScanDeviceGroups {
    /// - Parameter grouped: the saved rows that are in a group (`deviceGroupID != nil`).
    static func onePerDevice(_ scan: [DiscoveredDevice], grouped: [LocalDevice]) -> [DiscoveredDevice] {
        guard !grouped.isEmpty else { return scan }
        let devices = DeviceGroups.project(grouped)
        func device(of scanned: DiscoveredDevice) -> DeviceProjection? {
            let mac = DeviceMatcher.normalizedMAC(scanned.macAddress)
            return devices.first { device in
                device.members.contains { member in
                    guard member.networkProfileID == scanned.networkProfileID || member.networkProfileID == nil else { return false }
                    if let mac, let memberMAC = DeviceMatcher.normalizedMAC(member.macAddress) {
                        return mac == memberMAC
                    }
                    return member.ipAddress == scanned.ipAddress
                }
            }
        }
        let owners = scan.map(device(of:))
        var kept: [UUID: Int] = [:]
        for (index, owner) in owners.enumerated() {
            guard let owner else { continue }
            if let earlier = kept[owner.id], scan[earlier].ipAddress == owner.ipAddress {
                continue
            }
            if kept[owner.id] == nil || scan[index].ipAddress == owner.ipAddress {
                kept[owner.id] = index
            }
        }
        let keptIndexes = Set(kept.values)
        return scan.indices.filter { owners[$0] == nil || keptIndexes.contains($0) }.map { scan[$0] }
    }
}
