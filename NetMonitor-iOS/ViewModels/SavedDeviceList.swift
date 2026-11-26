import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData

/// The devices the iPhone's device list and dashboard card show (#583): the network's saved
/// devices, each with its `PresenceFreshness` and last-seen time, plus the live scan's devices not
/// saved yet ("Found in this scan"), so a scan in progress, or a stopped one, still shows what it
/// found. Sorted and filtered by presence; past devices left out unless shown. A group of rows that
/// are one device's interfaces is one entry (#594): projected first, then filtered and sorted.
///
/// While the connected Mac's inventory is live (#585), a device the Mac knows shows the Mac's
/// state with that source, the phone's own sighting is labelled apart, and devices only the Mac
/// knows are listed (shown, never saved, not opened). Without it the list is the phone's own.
@MainActor
struct SavedDeviceList {
    /// How the list sorts; online first for `.status`, then not checked recently, then offline.
    enum Sort: String, CaseIterable {
        case ip = "IP Address"
        case name = "Name"
        case latency = "Latency"
        case status = "Status"
    }

    /// A row of the list.
    enum Entry: Identifiable {
        /// A saved device (a row, or a group of interfaces), shown with its presence.
        case saved(DeviceProjection)
        /// A device a scan found that has no saved row yet: online only while that sighting is recent.
        case found(DiscoveredDevice)
        /// A device only the connected Mac knows (#585): shown with the Mac's state, never saved.
        case mac(MacInventory.Record)

        var id: String {
            switch self {
            case .saved(let device): "saved-\(device.id)"
            case .found(let device): "found-\(device.id)"
            case .mac(let record): "mac-\(record.id)"
            }
        }

        var ipAddress: String {
            switch self {
            case .saved(let device): device.ipAddress
            case .found(let device): device.ipAddress
            case .mac(let record): record.ipAddress
            }
        }

        /// Where tapping the row goes: a saved device by its ID (#584; a group's own ID, #594), so
        /// an address DHCP gave another device never opens the wrong one; a found device by its
        /// address. A device only the Mac knows opens nothing: detail would save it (#585).
        var destination: AppDestination? {
            switch self {
            case .saved(let device): .savedDevice(id: device.id)
            case .found(let device):
                .deviceDetail(ipAddress: device.ipAddress, networkID: device.networkProfileID, macAddress: device.macAddress)
            case .mac: nil
            }
        }

        var displayName: String {
            switch self {
            case .saved(let device): device.displayName
            case .found(let device): device.displayName
            case .mac(let record): record.name
            }
        }
    }

    let entries: [Entry]
    /// The N in "Show past devices (N)".
    let pastCount: Int
    let presence: PresenceSnapshot
    /// The Mac's inventory for this list's network, computed once by `MacInventoryModel` (#585);
    /// `.none` when it isn't live or is another network's.
    let overlay: MacInventoryOverlay

    /// - Parameters:
    ///   - saved: saved rows, complete groups (``recentRows(network:in:)``); those of `network`
    ///     (or of none) are listed, one entry per device.
    ///   - live: the scan's devices, during or after it; those matching a saved row (by MAC, else
    ///     address) are that row's device, the rest are listed as found in this scan.
    ///   - overlay: the connected Mac's inventory (#585), used only when it is this network's.
    init(
        saved: [LocalDevice], live: [DiscoveredDevice] = [], network: UUID?, sort: Sort, showPast: Bool, presence: PresenceSnapshot,
        overlay: MacInventoryOverlay = .none
    ) {
        let rows = saved.filter { $0.networkProfileID == network || $0.networkProfileID == nil }
        self.presence = presence
        let overlay = overlay.applies(to: network) ? overlay : .none
        self.overlay = overlay
        let unsaved = live.filter { device in
            (device.networkProfileID == network || device.networkProfileID == nil) && !rows.contains { Self.matches($0, device) }
        }
        // At a Mac record's address, a live phone sighting is the phone's; a cached one gives way to
        // the Mac's current status (Devin on #624).
        func atMacRecord(_ device: DiscoveredDevice) -> Bool {
            overlay.macOnly.contains { record in record.members.contains { $0.ipAddress == device.ipAddress } }
        }
        let found = unsaved.filter { !($0.isCached && atMacRecord($0)) }
        // Past devices are filtered after matching: one the Mac has online now is shown (#585 review 4).
        let all = DeviceList.devices(rows, filter: DeviceListFilter(showPast: true), presence: presence, sort: .ipAddress, ascending: true)
        let shown = all.filter { overlay.isShown($0, showPast: showPast, presence: presence) }
        pastCount = all.count { presence.isPast($0) && !overlay.isShown($0, showPast: false, presence: presence) }
        let macOnly = overlay.macOnly.filter { record in !found.contains { device in record.members.contains { $0.ipAddress == device.ipAddress } } }
        entries = Self.sorted(
            shown.map(Entry.saved) + found.map(Entry.found) + macOnly.map(Entry.mac), by: sort,
            freshness: { Self.freshness($0, presence, overlay) },
            // A latency hidden beside the Mac's "Offline" doesn't sort the row first.
            latency: { Self.freshness($0, presence, overlay).isOnline ? Self.latency($0, presence) : .infinity }
        )
    }

    /// The saved devices the list reads (#594): the network's `fetchLimit` most recently seen
    /// devices plus those saved before rows had a network, each paged by device by Core
    /// (`DeviceGroups.recentDevices`), as complete groups, most recent first, at most `fetchLimit`
    /// devices.
    static func recentRows(network: UUID?, in context: ModelContext) -> [LocalDevice] {
        DeviceGroups.listedRows(network: network, limit: fetchLimit, in: context)
    }

    static let fetchLimit = DeviceGroups.listedRowLimit

    /// Devices online now, counting devices found by a recent scan and, while it is live, the Mac's.
    var onlineCount: Int {
        entries.count { Self.freshness($0, presence, overlay).isOnline }
    }

    // MARK: - The Mac's inventory (#585)

    /// "From your Mac · scanned 2 min ago" while the Mac's inventory is live.
    var sourceText: String? {
        overlay.inventory?.sourceText(now: presence.now)
    }

    /// The Mac's record of a saved device, while the inventory is live.
    func macRecord(for device: DeviceProjection) -> MacInventory.Record? {
        overlay.record(for: device)
    }

    /// The device's state: the Mac's while it has a record, else the phone's own.
    func freshness(of device: DeviceProjection) -> PresenceFreshness {
        overlay.freshness(of: device, presence: presence)
    }

    /// "Online · from your Mac · Last seen 2 min ago", or the phone's own "Online · Last seen …".
    func statusText(_ device: DeviceProjection) -> String {
        macRecord(for: device)?.statusText(now: presence.now) ?? presence.statusText(device)
    }

    /// "5 min ago": the Mac's last seen while it has a record, else the phone's.
    func relativeLastSeen(_ device: DeviceProjection) -> String {
        PresenceFreshness.relativeText(since: macRecord(for: device)?.lastSeen ?? device.lastSeen, now: presence.now)
    }

    func accessibilityText(_ device: DeviceProjection) -> String {
        macRecord(for: device)?.accessibilityText(now: presence.now) ?? presence.accessibilityText(device)
    }

    /// "Seen by this iPhone at 10:42 AM": only when the phone's own latest scan saw the device,
    /// with that scan's time, while the Mac's inventory is shown (#585 review 8).
    func phoneSightingText(_ device: DeviceProjection) -> String? {
        overlay.phoneSighting(for: device).map { MacInventory.phoneSightingText($0, now: presence.now) }
    }

    /// "Acme Doorbell 2 · from your Mac": the Mac's maker and model when the phone has neither
    /// (#585 review 9, #427). Shown only, never saved.
    func macIdentityText(_ device: DeviceProjection) -> String? {
        guard device.primary.maker == nil, device.primary.modelName == nil, let record = macRecord(for: device) else { return nil }
        let identity = [record.maker, record.model].compactMap { $0 }.joined(separator: " ")
        return identity.isEmpty ? nil : "\(identity) · \(MacInventory.Record.source)"
    }

    /// A found device is online while its sighting is within the grace interval; a stopped or
    /// cached scan's device goes "not checked recently" like any saved row (#583).
    func freshness(of device: DiscoveredDevice) -> PresenceFreshness {
        PresenceFreshness.isRecent(device.discoveredAt, now: presence.now, policy: presence.policy) ? .online : .notCheckedRecently
    }

    /// "Found in this scan", or "Not checked recently · found 2 hours ago" for an old sighting.
    func foundText(_ device: DiscoveredDevice) -> String {
        guard freshness(of: device) == .notCheckedRecently else { return "Found in this scan" }
        return "\(PresenceFreshness.notCheckedRecently.label) · found \(PresenceFreshness.relativeText(since: device.discoveredAt, now: presence.now))"
    }

    /// The current member's last latency, only while the device is online: an old one is no news.
    /// Never beside the Mac's "Offline" (#585).
    func latencyText(_ device: DeviceProjection) -> String? {
        guard freshness(of: device).isOnline, let latency = presence.currentLatency(device) else { return nil }
        return latency < 1 ? "<1 ms" : "\(Int(latency.rounded())) ms"
    }

    /// The same device: an identical real MAC, else the same address.
    private static func matches(_ row: LocalDevice, _ device: DiscoveredDevice) -> Bool {
        if let mac = DeviceMatcher.normalizedMAC(device.macAddress), let rowMAC = DeviceMatcher.normalizedMAC(row.macAddress) {
            return mac == rowMAC
        }
        return row.ipAddress == device.ipAddress
    }

    private static func sorted(
        _ entries: [Entry], by sort: Sort, freshness: (Entry) -> PresenceFreshness, latency: (Entry) -> Double
    ) -> [Entry] {
        let byIP = entries.sorted { DeviceList.compareIPAddresses($0.ipAddress, $1.ipAddress) }
        switch sort {
        case .ip:
            return byIP
        case .name:
            return byIP.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        case .latency:
            return byIP.sorted { latency($0) < latency($1) }
        case .status:
            return PresenceFreshness.allCases.flatMap { state in byIP.filter { freshness($0) == state } }
        }
    }

    private static func freshness(_ entry: Entry, _ presence: PresenceSnapshot, _ overlay: MacInventoryOverlay) -> PresenceFreshness {
        switch entry {
        case .saved(let device):
            overlay.freshness(of: device, presence: presence)
        case .found(let device):
            PresenceFreshness.isRecent(device.discoveredAt, now: presence.now, policy: presence.policy) ? .online : .notCheckedRecently
        case .mac(let record):
            record.state
        }
    }

    private static func latency(_ entry: Entry, _ presence: PresenceSnapshot) -> Double {
        switch entry {
        case .saved(let device): presence.currentLatency(device) ?? .infinity
        case .found(let device):
            PresenceFreshness.isRecent(device.discoveredAt, now: presence.now, policy: presence.policy) ? device.latency ?? .infinity : .infinity
        case .mac: .infinity
        }
    }
}

/// The saved rows a list shows (#594), read through ``SavedDeviceList/recentRows(network:in:)``,
/// which pages by device; a `@Query` can't. Refreshed when the list appears and after every save.
@MainActor
@Observable
final class SavedDeviceRows {
    private(set) var rows: [LocalDevice] = []
    /// False until the first read, so a list doesn't flash "No Devices Found".
    private(set) var isLoaded = false

    func refresh(network: UUID?, in context: ModelContext) {
        rows = SavedDeviceList.recentRows(network: network, in: context)
        isLoaded = true
    }
}
