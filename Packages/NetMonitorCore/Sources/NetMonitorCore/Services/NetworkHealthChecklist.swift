import CResolv
import Foundation
#if os(macOS)
import SystemConfiguration
#endif

// MARK: - Health Check Model

/// One row of the network health checklist (#397).
public struct HealthCheck: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, CaseIterable {
        case gateway
        case dnsServers
        case internet
        case vpn
        case wifiSignal
        case devices
        case linkSpeed

        public var title: String {
            switch self {
            case .gateway: "Router"
            case .dnsServers: "DNS servers"
            case .internet: "Internet"
            case .vpn: "VPN"
            case .wifiSignal: "Wi-Fi signal"
            case .devices: "Devices"
            case .linkSpeed: "Link speed"
            }
        }
    }

    public enum Status: String, Sendable {
        case pass
        case warn
        /// The platform couldn't measure it; shown neutrally rather than guessed.
        case unavailable
    }

    public let kind: Kind
    public let status: Status
    /// One plain sentence explaining the result.
    public let message: String

    public var id: Kind { kind }

    public init(kind: Kind, status: Status, message: String) {
        self.kind = kind
        self.status = status
        self.message = message
    }
}

/// Measured inputs for the checklist. A `nil` field means the platform could not
/// measure it (for example Wi-Fi signal on Ethernet), and its row is left out.
public struct HealthCheckInputs: Sendable, Equatable {
    /// What the system reported about configured DNS servers.
    public enum DNSServers: Sendable, Equatable {
        case servers([String])
        /// The platform couldn't report them.
        case unavailable
    }

    public var gatewayReachable: Bool?
    public var dnsServers: DNSServers?
    public var internetReachable: Bool?
    public var vpnActive: Bool?
    public var wifiRSSI: Int?
    public var deviceCount: Int?
    public var linkSpeedMbps: Double?

    public init(
        gatewayReachable: Bool? = nil,
        dnsServers: DNSServers? = nil,
        internetReachable: Bool? = nil,
        vpnActive: Bool? = nil,
        wifiRSSI: Int? = nil,
        deviceCount: Int? = nil,
        linkSpeedMbps: Double? = nil
    ) {
        self.gatewayReachable = gatewayReachable
        self.dnsServers = dnsServers
        self.internetReachable = internetReachable
        self.vpnActive = vpnActive
        self.wifiRSSI = wifiRSSI
        self.deviceCount = deviceCount
        self.linkSpeedMbps = linkSpeedMbps
    }
}

// MARK: - Checklist Evaluation

/// Turns measured inputs into pass/warn rows. Pure, so it is tested without a network.
/// The checklist sits beside the health score; it does not change the score.
public enum NetworkHealthChecklist {

    /// Link speeds below this many Mbps are flagged as slow.
    public static let slowLinkSpeedMbps: Double = 50

    public static func evaluate(_ inputs: HealthCheckInputs) -> [HealthCheck] {
        var checks: [HealthCheck] = []

        if let reachable = inputs.gatewayReachable {
            checks.append(reachable
                ? HealthCheck(kind: .gateway, status: .pass, message: "Your router is answering.")
                : HealthCheck(kind: .gateway, status: .warn, message: "Your router didn't answer. Check your connection to it."))
        }

        switch inputs.dnsServers {
        case nil:
            break
        case .unavailable:
            checks.append(HealthCheck(kind: .dnsServers, status: .unavailable, message: "Configured DNS unavailable on this device."))
        case let .servers(servers):
            if servers.isEmpty {
                checks.append(HealthCheck(kind: .dnsServers, status: .warn, message: "No DNS servers are set, so websites may not load."))
            } else {
                let noun = servers.count == 1 ? "server is" : "servers are"
                checks.append(HealthCheck(
                    kind: .dnsServers,
                    status: .pass,
                    message: "\(servers.count) DNS \(noun) set: \(servers.prefix(2).joined(separator: ", "))."
                ))
            }
        }

        if let reachable = inputs.internetReachable {
            checks.append(reachable
                ? HealthCheck(kind: .internet, status: .pass, message: "The internet is reachable.")
                : HealthCheck(kind: .internet, status: .warn, message: "The internet can't be reached right now."))
        }

        if let vpnActive = inputs.vpnActive {
            checks.append(vpnActive
                ? HealthCheck(kind: .vpn, status: .warn, message: "A VPN is on. It can slow traffic and hide devices on your network.")
                : HealthCheck(kind: .vpn, status: .pass, message: "No VPN is on."))
        }

        if let rssi = inputs.wifiRSSI {
            let quality = RSSIQuality(rssi: rssi)
            let isGood = quality == .excellent || quality == .good
            checks.append(HealthCheck(
                kind: .wifiSignal,
                status: isGood ? .pass : .warn,
                message: isGood
                    ? "Wi-Fi signal is \(quality.label.lowercased()) (\(rssi) dBm)."
                    : "Wi-Fi signal is \(quality.label.lowercased()) (\(rssi) dBm). Move closer to the router."
            ))
        }

        if let count = inputs.deviceCount {
            if count == 0 {
                checks.append(HealthCheck(kind: .devices, status: .warn, message: "No devices found yet. Run a scan."))
            } else {
                let noun = count == 1 ? "device" : "devices"
                checks.append(HealthCheck(kind: .devices, status: .pass, message: "\(count) \(noun) found on your network."))
            }
        }

        if let speed = inputs.linkSpeedMbps, speed > 0 {
            let text = String(format: "%.0f Mbps", speed)
            checks.append(speed < slowLinkSpeedMbps
                ? HealthCheck(kind: .linkSpeed, status: .warn, message: "Link speed is \(text), which is slow.")
                : HealthCheck(kind: .linkSpeed, status: .pass, message: "Link speed is \(text)."))
        }

        return checks
    }
}

// MARK: - System DNS Configuration

/// The DNS servers the system resolver uses. macOS reads them from SystemConfiguration
/// (`State:/Network/Global/DNS`); iOS asks the resolver library (`res_ninit`).
public enum SystemDNSConfiguration {

    /// Server addresses, or `.unavailable` when the platform can't report them.
    public static func current() -> HealthCheckInputs.DNSServers {
        #if os(macOS)
        return fromDynamicStore()
        #else
        return fromResolver()
        #endif
    }

    /// Just the addresses, or nil when unavailable (used to pick the "Your DNS" server).
    public static func currentNameservers() -> [String]? {
        if case let .servers(servers) = current() {
            return servers
        }
        return nil
    }

    /// The resolver falls back to loopback when it has no configuration, so a
    /// loopback-only answer means "unknown", not a real server.
    static func usable(_ servers: [String]) -> HealthCheckInputs.DNSServers {
        let isLoopback: (String) -> Bool = { $0 == "127.0.0.1" || $0 == "::1" }
        return servers.isEmpty || servers.allSatisfy(isLoopback) ? .unavailable : .servers(servers)
    }

    #if os(macOS)
    private static func fromDynamicStore() -> HealthCheckInputs.DNSServers {
        guard let store = SCDynamicStoreCreate(nil, "NetMonitor" as CFString, nil, nil),
              let value = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
              let servers = value["ServerAddresses"] as? [String]
        else {
            return .unavailable
        }
        return .servers(servers)
    }
    #endif

    private static func fromResolver() -> HealthCheckInputs.DNSServers {
        var buffer = [CChar](repeating: 0, count: 1024)
        let count = nm_copy_dns_servers(&buffer, Int32(buffer.count))
        guard count >= 0 else { return .unavailable }
        let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return usable(text.split(separator: "\n").map(String.init))
    }
}
