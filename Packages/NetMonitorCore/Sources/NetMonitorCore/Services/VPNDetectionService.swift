import Foundation
import Network

// MARK: - VPN Supporting Types

/// VPN connection status.
public struct VPNStatus: Sendable, Equatable {
    public let isActive: Bool
    public let interfaceName: String?
    public let protocolType: VPNProtocolType
    public let connectedSince: Date?

    public init(
        isActive: Bool,
        interfaceName: String? = nil,
        protocolType: VPNProtocolType = .unknown,
        connectedSince: Date? = nil
    ) {
        self.isActive = isActive
        self.interfaceName = interfaceName
        self.protocolType = protocolType
        self.connectedSince = connectedSince
    }

    public static let inactive = VPNStatus(isActive: false)
}

/// Detected VPN protocol type.
public enum VPNProtocolType: String, Sendable {
    case wireguard  = "WireGuard"
    case ipsec      = "IPSec"
    case openvpn    = "OpenVPN"
    case l2tp       = "L2TP"
    case pptp       = "PPTP"
    case ikev2      = "IKEv2"
    case other      = "Other"
    case unknown    = "Unknown"

    /// Infer protocol from interface name prefix.
    public static func from(interfaceName: String) -> VPNProtocolType {
        let lower = interfaceName.lowercased()
        if lower.hasPrefix("utun") { return .other }
        if lower.hasPrefix("ipsec") { return .ipsec }
        if lower.hasPrefix("ppp") { return .pptp }
        if lower.hasPrefix("l2tp") { return .l2tp }
        if lower.hasPrefix("ikev2") { return .ikev2 }
        return .unknown
    }
}

// MARK: - VPNDetectionServiceProtocol

/// Protocol for VPN detection.
public protocol VPNDetectionServiceProtocol: AnyObject, Sendable {
    /// Current VPN status (read-only snapshot).
    var status: VPNStatus { get }
    /// Start monitoring for VPN changes.
    func startMonitoring()
    /// Stop monitoring.
    func stopMonitoring()
    /// Async stream of VPN status updates.
    func statusStream() -> AsyncStream<VPNStatus>
}

// MARK: - VPNDetectionService

/// Detects active VPN connections using NWPathMonitor.
public final class VPNDetectionService: VPNDetectionServiceProtocol, @unchecked Sendable {

    private let lock = NSLock()
    private var _status: VPNStatus = .inactive
    private var monitor: NWPathMonitor?
    private let queue = DispatchQueue(label: "com.netmonitor.vpn", qos: .utility)

    // Continuation for streaming status updates
    private var continuations: [UUID: AsyncStream<VPNStatus>.Continuation] = [:]
    private var connectionStart: Date?

    public init() {}

    public var status: VPNStatus {
        lock.withLock { _status }
    }

    public func startMonitoring() {
        lock.lock()
        guard monitor == nil else { lock.unlock(); return }
        let m = NWPathMonitor()
        monitor = m
        lock.unlock()

        m.pathUpdateHandler = { [weak self] path in
            self?.handlePathUpdate(path)
        }
        m.start(queue: queue)
    }

    public func stopMonitoring() {
        lock.lock()
        monitor?.cancel()
        monitor = nil
        lock.unlock()
    }

    public func statusStream() -> AsyncStream<VPNStatus> {
        AsyncStream { [weak self] continuation in
            guard let self else {
                continuation.finish()
                return
            }
            let id = UUID()
            lock.lock()
            continuations[id] = continuation
            lock.unlock()

            continuation.onTermination = { [weak self] _ in
                self?.lock.lock()
                self?.continuations.removeValue(forKey: id)
                self?.lock.unlock()
            }

            // Immediately emit current status
            continuation.yield(self.status)
        }
    }

    // MARK: - Private

    private func handlePathUpdate(_ path: NWPath) {
        let vpnInterface = detectVPNInterface(in: path)
        let isActive = vpnInterface != nil || path.usesInterfaceType(.other)

        let newStatus: VPNStatus
        if isActive {
            let ifName = vpnInterface
            let proto = ifName.map { VPNProtocolType.from(interfaceName: $0) } ?? .other
            let start = lock.withLock { connectionStart ?? Date() }
            lock.lock()
            if connectionStart == nil { connectionStart = Date() }
            lock.unlock()
            newStatus = VPNStatus(
                isActive: true,
                interfaceName: vpnInterface,
                protocolType: proto,
                connectedSince: start
            )
        } else {
            lock.lock()
            connectionStart = nil
            lock.unlock()
            newStatus = .inactive
        }

        lock.lock()
        _status = newStatus
        let conts = Array(continuations.values)
        lock.unlock()

        for cont in conts {
            cont.yield(newStatus)
        }
    }

    /// Returns the first VPN-like interface name found in the path, or nil.
    private func detectVPNInterface(in path: NWPath) -> String? {
        // Check for utun, ipsec, ppp interfaces which indicate VPN tunnels
        let vpnPrefixes = ["utun", "ipsec", "ppp", "l2tp", "tun"]
        for prefix in vpnPrefixes {
            // NWPath doesn't expose interface names directly in all OS versions;
            // use path.usesInterfaceType(.other) as primary signal, then try
            // to get interface name via SCNetworkInterface if available.
            if path.usesInterfaceType(.other) {
                // The interface name hints come from the path description
                let desc = "\(path)"
                if let range = desc.range(of: prefix, options: .caseInsensitive) {
                    // Extract the interface token (e.g. "utun2")
                    let start = range.lowerBound
                    let end = desc[start...].firstIndex(where: { $0 == " " || $0 == "," || $0 == ")" }) ?? desc.endIndex
                    let name = String(desc[start..<end])
                    if !name.isEmpty { return name }
                    return prefix + "0"
                }
            }
        }
        return nil
    }
}
