import Foundation

// MARK: - Checks (#451)

/// One check a troubleshooting script runs through the app's existing services. The app picks
/// every check; the model never chooses or calls one (the #447 wave-2 spike found its tool choice
/// unreliable for vague symptoms).
public enum TroubleshootCheck: Equatable, Sendable {
    public enum PingTarget: Equatable, Sendable {
        /// The router; its address is found when the step runs.
        case gateway
        /// A saved device: its display name and address.
        case device(String, String)
        /// A website host.
        case host(String)

        /// How results and findings name the target.
        public var name: String {
            switch self {
            case .gateway: "your router"
            case let .device(name, _): name
            case let .host(host): host
            }
        }
    }

    public enum DNSRole: Equatable, Sendable {
        /// A well-known name, timed to judge the DNS server.
        case internet
        /// The website the user named.
        case website
    }

    case ping(PingTarget, count: Int)
    case dnsLookup(host: String, role: DNSRole)
    /// The Wi-Fi signal: one reading now, or several spread over `TroubleshootState.readingSpan`.
    case wifiSignal(readings: Int)
    /// Download speed, compared with the last saved test. Optional: the user can skip it.
    case speedTest
    /// A TCP connect to each port.
    case ports(host: String, ports: [Int])

    /// The step's heading.
    public var title: String {
        switch self {
        case let .ping(target, count): "Ping \(target.name) × \(count)"
        case let .dnsLookup(host, _): "Look up \(host)"
        case let .wifiSignal(readings): readings == 1 ? "Wi-Fi signal now" : "Wi-Fi signal, \(readings) readings over 10 s"
        case .speedTest: "Speed test (about 20 s, optional)"
        case let .ports(host, ports): ports == [443] ? "Connect to \(host) on port 443" : "Probe \(ports.count) known open ports"
        }
    }

    /// Whether the user can skip this step and go on with the next.
    public var isSkippable: Bool { self == .speedTest }
}

/// The fixed diagnostic script for each kind of symptom (#451). At most `maximumSteps` steps.
public enum TroubleshootScript {
    public static let maximumSteps = 6
    /// Most known open ports a device probe tries.
    public static let maximumPorts = 8
    /// The name timed to judge DNS: well known and served from many places.
    public static let dnsProbeHost = "apple.com"

    /// The checks for `kind`. `device` is needed for `deviceUnreachable` and `host` for
    /// `websiteNotLoading`; without them those scripts are empty.
    public static func checks(for kind: SymptomKind, device: TroubleshootDevice? = nil, host: String? = nil) -> [TroubleshootCheck] {
        switch kind {
        case .slowOrUnstableInternet:
            return [.ping(.gateway, count: 10), .dnsLookup(host: dnsProbeHost, role: .internet), .wifiSignal(readings: 1), .speedTest]
        case .deviceUnreachable:
            guard let device else { return [] }
            var checks: [TroubleshootCheck] = [.ping(.device(device.displayName, device.ipAddress), count: 5)]
            let ports = Array(device.openPorts.prefix(maximumPorts))
            if !ports.isEmpty {
                checks.append(.ports(host: device.ipAddress, ports: ports))
            }
            checks.append(.ping(.gateway, count: 5))
            return checks
        case .weakWiFi:
            return [.wifiSignal(readings: 1), .wifiSignal(readings: 3)]
        case .websiteNotLoading:
            guard let host else { return [] }
            return [.dnsLookup(host: host, role: .website), .ping(.host(host), count: 5), .ports(host: host, ports: [443]), .ping(.gateway, count: 5)]
        case .unsupported:
            return []
        }
    }
}

// MARK: - Devices

/// A saved device as the troubleshooter sees it (#451): its stable identity, the identity seam's
/// name, type and maker, its address and the ports scans found open.
public struct TroubleshootDevice: DevicePhraseMatchable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var displayName: String
    public var deviceType: DeviceType
    public var maker: String?
    public var ipAddress: String
    /// Ports scans found open (`LocalDevice.openPorts`), probed again by the script.
    public var openPorts: [Int]

    public init(id: UUID, displayName: String, deviceType: DeviceType, maker: String?, ipAddress: String, openPorts: [Int] = []) {
        self.id = id
        self.displayName = displayName
        self.deviceType = deviceType
        self.maker = maker
        self.ipAddress = ipAddress
        self.openPorts = openPorts
    }

    /// A saved device as the troubleshooter sees it. The maker leaves out model suggestions.
    public init(_ device: LocalDevice) {
        self.init(
            id: device.id,
            displayName: device.displayName,
            deviceType: device.deviceType,
            maker: device.makerExcludingSuggestions,
            ipAddress: device.ipAddress,
            openPorts: device.openPorts ?? []
        )
    }
}

// MARK: - Results

/// What a ping step measured.
public struct PingSummary: Equatable, Sendable {
    public let target: TroubleshootCheck.PingTarget
    public let sent: Int
    public let received: Int
    /// Mean round trip of the replies; nil without replies.
    public let averageMs: Double?
    /// Mean difference between consecutive replies' round trips; nil under two replies.
    public let jitterMs: Double?

    public init(target: TroubleshootCheck.PingTarget, sent: Int, received: Int, averageMs: Double?, jitterMs: Double?) {
        self.target = target
        self.sent = sent
        self.received = received
        self.averageMs = averageMs
        self.jitterMs = jitterMs
    }

    /// The summary of `times`, the round trips of the replies, out of `sent` pings.
    public init(target: TroubleshootCheck.PingTarget, sent: Int, times: [Double]) {
        let jitter = times.count > 1 ? zip(times, times.dropFirst()).map { abs($1 - $0) }.reduce(0, +) / Double(times.count - 1) : nil
        self.init(target: target, sent: sent, received: times.count,
                  averageMs: times.isEmpty ? nil : times.reduce(0, +) / Double(times.count), jitterMs: jitter)
    }

    /// Lost pings, in percent of those sent.
    public var lossPercent: Double {
        sent > 0 ? Double(sent - received) / Double(sent) * 100 : 0
    }
}

/// One Wi-Fi signal reading.
public struct WiFiReading: Equatable, Sendable {
    public let rssi: Int
    public let noise: Int?

    public init(rssi: Int, noise: Int?) {
        self.rssi = rssi
        self.noise = noise
    }
}

/// What one step measured, shown raw beside its heading.
public enum TroubleshootResult: Equatable, Sendable {
    case ping(PingSummary)
    /// Nil milliseconds: the name didn't resolve.
    case dns(host: String, milliseconds: Double?)
    /// Empty: no signal reading on this device or connection.
    case wifi([WiFiReading])
    case speed(downloadMbps: Double, baselineMbps: Double?)
    case ports(host: String, open: [Int], closed: [Int])
    /// The step couldn't measure, with why ("No router address found").
    case unavailable(String)
    case skipped

    /// The raw result line.
    public var text: String {
        switch self {
        case let .ping(summary):
            var parts = ["\(summary.received) of \(summary.sent) replies", "\(Self.number(summary.lossPercent))% loss"]
            if let average = summary.averageMs {
                parts.append("avg \(Self.number(average)) ms")
            }
            if let jitter = summary.jitterMs {
                parts.append("jitter \(Self.number(jitter)) ms")
            }
            return parts.joined(separator: " · ")
        case let .dns(host, milliseconds):
            return milliseconds.map { "\(host) resolved in \(Self.number($0)) ms" } ?? "\(host) didn't resolve"
        case let .wifi(readings):
            guard !readings.isEmpty else { return "No signal reading on this connection" }
            let rssi = readings.map { String($0.rssi) }.joined(separator: ", ") + " dBm"
            let noise = readings.compactMap(\.noise)
            return noise.isEmpty ? "Signal \(rssi)" : "Signal \(rssi) · noise \(noise.map(String.init).joined(separator: ", ")) dBm"
        case let .speed(download, baseline):
            let last = baseline.map { " (last saved test \(Self.number($0)) Mbps)" } ?? " (no saved test to compare)"
            return "Download \(Self.number(download)) Mbps" + last
        case let .ports(_, open, closed):
            var parts: [String] = []
            if !open.isEmpty {
                parts.append("Open: " + open.map(String.init).joined(separator: ", "))
            }
            if !closed.isEmpty {
                parts.append("No answer: " + closed.map(String.init).joined(separator: ", "))
            }
            return parts.joined(separator: " · ")
        case let .unavailable(reason):
            return reason
        case .skipped:
            return "Skipped"
        }
    }

    /// `value` with at most one decimal, and none when it is whole: 10.26 → "10.3", 100.0 → "100".
    static func number(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
    }
}
