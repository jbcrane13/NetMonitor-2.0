import Foundation
import NetworkScanKit

/// Lists the router's UPnP port forwards on the local network (#400). Read-only: only
/// `GetGenericPortMappingEntry` is ever sent.
public struct UPnPPortMappingService: UPnPPortMappingServiceProtocol {
    public init() {}

    public func readPortMappings(interface: String) async -> UPnPPortMappingReport? {
        guard let network = NetworkUtilities.detectLocalIPv4Network(interface: interface) else { return nil }
        let localIP = NetworkUtilities.detectLocalIPAddress(interface: interface)
        return await UPnPPortMappingReader.read(localIP: localIP, subnetFilter: { network.contains(ipAddress: $0) })
    }
}
