import Foundation
import NetMonitorCore

/// The network's saved device rows as the iPhone's device list and dashboard card show them
/// (#583): each with its `PresenceFreshness` and last-seen time, sorted and filtered by it, past
/// devices left out unless shown. The rows are kept current by `DeviceRecordUpdater` after every
/// scan, so offline devices and a network not checked recently show too.
@MainActor
struct SavedDeviceList {
    /// The sorts the saved list offers; the live scan list has its own (`.source`).
    static let sortOrders: [DeviceSortOrder] = [.ip, .name, .latency, .status]

    let rows: [LocalDevice]
    /// The N in "Show past devices (N)".
    let pastCount: Int
    let presence: PresenceSnapshot

    init(saved: [LocalDevice], network: UUID?, sort: DeviceSortOrder, showPast: Bool, presence: PresenceSnapshot) {
        let network = saved.filter { $0.networkProfileID == network }
        self.presence = presence
        pastCount = DeviceList.pastCount(network, search: "", presence: presence)
        let core: NetMonitorCore.DeviceSortOrder = switch sort {
        case .ip, .source: .ipAddress
        case .name: .name
        case .latency: .latency
        case .status: .status
        }
        let sorted = DeviceList.rows(network, search: "", onlineOnly: false, showPast: showPast, presence: presence, sort: core, ascending: true)
        // The status sort keeps addresses in order within each state.
        rows = sort == .status ? Self.stableByStatus(sorted, presence: presence) : sorted
    }

    /// Rows online now.
    var onlineCount: Int {
        rows.count { presence.freshness(of: $0).isOnline }
    }

    /// "Online · Last seen 5 min ago".
    func statusText(_ device: LocalDevice) -> String {
        "\(presence.freshness(of: device).label) · \(presence.lastSeenText(device))"
    }

    /// The last latency, only while the device is online: an old one is no news.
    func latencyText(_ device: LocalDevice) -> String? {
        guard presence.freshness(of: device).isOnline, let latency = device.lastLatency else { return nil }
        return latency < 1 ? "<1 ms" : "\(Int(latency.rounded())) ms"
    }

    /// What every saved row's status means now: each network's last scan, as of the app's
    /// presence clock (`UITestBootstrap.presenceNow()`, the wall clock outside UI tests).
    static func currentPresence() -> PresenceSnapshot {
        ScanHistory().presenceSnapshot(now: UITestBootstrap.presenceNow())
    }

    private static func stableByStatus(_ rows: [LocalDevice], presence: PresenceSnapshot) -> [LocalDevice] {
        let byIP = rows.sorted { DeviceList.compareIPAddresses($0.ipAddress, $1.ipAddress) }
        return PresenceFreshness.allCases.flatMap { state in byIP.filter { presence.freshness(of: $0) == state } }
    }
}
