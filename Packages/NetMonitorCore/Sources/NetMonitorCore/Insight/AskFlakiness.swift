import Foundation

/// Which devices "Ask your network" calls flaky (#452). The app decides, so the model never has
/// to work out "flaky" itself: in the spike it checked reachability instead and called a flaky
/// device fine.
///
/// A drop is a "Device Left" event for the device in the range. A spike is one of this session's
/// latency samples above three times the median (and at least 50 ms over it). The samples carry
/// no times, so they count only in a range that includes now: never for yesterday. A device is flaky
/// when it dropped twice, dropped once and spiked, or spiked twice. Most drops rank first, then
/// most spikes, then name.
enum AskFlakiness {
    struct Entry: Equatable {
        let device: AskDevice
        let drops: Int
        let spikes: [Double]
    }

    static func rank(_ devices: [AskDevice], in range: AskRange, snapshot: AskSnapshot) -> [Entry] {
        let coversSession = range.interval(now: snapshot.now, calendar: snapshot.calendar).contains(snapshot.now)
        return devices.map { device in
            Entry(
                device: device, drops: drops(of: device.id, in: range, snapshot: snapshot),
                spikes: coversSession ? spikes(in: device.latencyHistory) : []
            )
        }
        .filter { $0.drops >= 2 || ($0.drops >= 1 && !$0.spikes.isEmpty) || $0.spikes.count >= 2 }
        .sorted { lhs, rhs in
            if lhs.drops != rhs.drops {
                return lhs.drops > rhs.drops
            }
            if lhs.spikes.count != rhs.spikes.count {
                return lhs.spikes.count > rhs.spikes.count
            }
            return lhs.device.displayName.localizedStandardCompare(rhs.device.displayName) == .orderedAscending
        }
    }

    static func drops(of id: UUID, in range: AskRange, snapshot: AskSnapshot) -> Int {
        let interval = range.interval(now: snapshot.now, calendar: snapshot.calendar)
        return snapshot.events.count { event in
            event.type == .deviceLeft && event.deviceID == id && interval.start <= event.timestamp && event.timestamp < interval.end
        }
    }

    /// The samples well above the median.
    static func spikes(in samples: [Double]) -> [Double] {
        guard samples.count >= 3 else { return [] }
        let sorted = samples.sorted()
        let middle = sorted.count / 2
        let median = sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
        let threshold = max(median * 3, median + 50)
        return samples.filter { $0 > threshold }
    }
}

/// The kinds of event the events tool filters by, named for the model.
/// The names say what each means: given "left" and "connectivity", the model filed "did anything
/// go offline" under connectivity.
enum AskEventKind: String, CaseIterable {
    case joined = "deviceJoined"
    case left = "deviceWentOffline"
    case connectivity = "thisDevicesConnectionChanged"
    case speed = "speedChanged"
    case gateway = "routerChanged"
    case vpn
    case scan = "scanFinished"

    /// The kind an argument names, by its name or a short one ("joined", "left"); nil (every
    /// kind) for "any" or anything else.
    static func named(_ text: String) -> AskEventKind? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { $0.rawValue.lowercased() == text || String(describing: $0) == text }
    }

    var types: Set<NetworkEventType> {
        switch self {
        case .joined: [.deviceJoined]
        case .left: [.deviceLeft]
        case .connectivity: [.connectivityChange]
        case .speed: [.speedChange]
        case .gateway: [.gatewayChange]
        case .vpn: [.vpnConnected, .vpnDisconnected]
        case .scan: [.scanComplete]
        }
    }

    var title: String {
        switch self {
        case .vpn: "VPN"
        default: types.first?.displayName ?? rawValue
        }
    }
}
