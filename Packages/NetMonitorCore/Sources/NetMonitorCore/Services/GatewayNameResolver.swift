import Foundation
import NetworkScanKit

/// Finds a device's DNS name with the system resolver, then by asking the gateway's DNS
/// server directly.
///
/// With a VPN such as Tailscale on, the system sends lookups to the VPN's DNS server, which
/// knows no LAN names. The router's DNS still answers for `192.168.2.4` →
/// `u7-pro.lan.example.net`, and that name is what identifies the device.
public struct GatewayNameResolver: Sendable {
    private let system: @Sendable (_ ipAddress: String) async -> String?
    private let gateway: @Sendable () -> String?
    private let query: @Sendable (_ reverseName: String, _ server: String) async -> String?

    public init(interface: String = "en0") {
        self.init(
            system: { await DeviceNameResolver().resolve(ipAddress: $0) },
            gateway: { NetworkUtilities.detectDefaultGateway(interface: interface) },
            query: { name, server in
                let records = try? await DNSUDPResolver.query(domain: name, type: .ptr, server: server, timeout: 2)
                return records?.first?.value
            }
        )
    }

    init(
        system: @escaping @Sendable (_ ipAddress: String) async -> String?,
        gateway: @escaping @Sendable () -> String?,
        query: @escaping @Sendable (_ reverseName: String, _ server: String) async -> String?
    ) {
        self.system = system
        self.gateway = gateway
        self.query = query
    }

    public func resolve(ipAddress: String) async -> String? {
        if let name = await system(ipAddress), !name.isEmpty {
            return name
        }
        guard let server = gateway(),
              let reverseName = DNSWireFormat.reverseLookupName(for: ipAddress),
              var name = await query(reverseName, server) else { return nil }
        if name.hasSuffix(".") {
            name.removeLast()
        }
        return name.isEmpty || name == ipAddress ? nil : name
    }
}
