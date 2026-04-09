//
//  NetworkInfoService.swift
//  NetMonitor
//
//  Actor for retrieving current network connection information.
//

import Foundation
import CoreWLAN
import NetMonitorCore
import Darwin

/// Error types for network info operations
enum NetworkInfoError: Error, LocalizedError {
    case permissionDenied
    case noActiveInterface
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Permission denied to access network information"
        case .noActiveInterface:
            return "No active network interface found"
        case .parsingFailed(let detail):
            return "Failed to parse network information: \(detail)"
        }
    }
}

/// Network connection information
struct ConnectionInfo {
    let connectionType: ConnectionType
    let ssid: String?
    let bssid: String?
    let signalStrength: Int?
    let channel: Int?
    let linkSpeed: Int?
    let interfaceName: String
}

/// Actor for retrieving network connection details
actor NetworkInfoService {
    /// Get current network connection information
    func getCurrentConnection() async throws -> ConnectionInfo {
        // Try CoreWLAN first for WiFi info
        let client = CWWiFiClient.shared()
        if let interface = client.interface() {
            // Check if WiFi interface is active (has power on)
            if interface.powerOn() {
                // SSID may be nil in sandbox without WiFi info entitlement
                // That's okay - we'll show "WiFi Connected" instead of network name
                return ConnectionInfo(
                    connectionType: .wifi,
                    ssid: interface.ssid(),
                    bssid: interface.bssid(),
                    signalStrength: interface.rssiValue(),
                    channel: interface.wlanChannel()?.channelNumber,
                    linkSpeed: interface.transmitRate() > 0 ? Int(interface.transmitRate()) : nil,
                    interfaceName: interface.interfaceName ?? "en0"
                )
            }
        }

        // Check for active network interfaces using ifaddrs
        if let activeInterface = getActiveNetworkInterface() {
            return activeInterface
        }

        throw NetworkInfoError.noActiveInterface
    }

    // MARK: - Active Interface Detection (ifaddrs)

    /// Get active network interface using getifaddrs
    private func getActiveNetworkInterface() -> ConnectionInfo? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            let isUp = (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING)
            let isLoopback = (flags & IFF_LOOPBACK) != 0

            guard isUp, !isLoopback else { continue }

            let addr = ptr.pointee.ifa_addr.pointee
            guard addr.sa_family == UInt8(AF_INET) || addr.sa_family == UInt8(AF_INET6) else { continue }

            let name = String(cString: ptr.pointee.ifa_name)

            // Skip non-physical interfaces
            guard name.hasPrefix("en") else { continue }

            // en0 is typically WiFi on Mac laptops, Ethernet on desktops
            // en1+ are typically additional Ethernet/Thunderbolt interfaces
            let isLikelyEthernet = name != "en0" || !isWiFiAvailable()

            return ConnectionInfo(
                connectionType: isLikelyEthernet ? .ethernet : .wifi,
                ssid: nil,
                bssid: nil,
                signalStrength: nil,
                channel: nil,
                linkSpeed: nil,
                interfaceName: name
            )
        }

        return nil
    }

    /// Check if WiFi is available and powered on
    private func isWiFiAvailable() -> Bool {
        CWWiFiClient.shared().interface()?.powerOn() ?? false
    }
}
