import Foundation
import NetMonitorCore
import Network

// MARK: - The Mac's inventory (#585)

/// What the current link says about the Mac's inventory: whether the Mac offered it and the path
/// the link runs on. Reset with the link.
struct CompanionInventoryLink {
    private(set) var offersInventory = false
    var path: CompanionLinkPath?

    /// Records a heartbeat, and calls `request` the first time one on this link offers the
    /// inventory, so the phone asks for it at once; the Mac then sends it after each scan.
    mutating func received(_ heartbeat: HeartbeatPayload, request: () -> Void) {
        guard heartbeat.offersInventory, !offersInventory else { return }
        offersInventory = true
        request()
    }
}

extension MacConnectionService {
    /// Whether the Mac on this link advertised `inventory.v1`; false once the link ends.
    var macOffersInventory: Bool { inventoryLink.offersInventory }
    /// The link's path, read when it came up; nil without a link.
    var linkPath: CompanionLinkPath? { inventoryLink.path }
}

extension CompanionLinkPath {
    /// The link's interface and the Mac's address on it, from the connection's current path. A VPN
    /// tunnel is `.other`.
    init?(_ path: NWPath?) {
        guard let path else { return nil }
        let interface: Interface = if path.usesInterfaceType(.other) {
            .other
        } else if path.usesInterfaceType(.wifi) {
            .wifi
        } else if path.usesInterfaceType(.wiredEthernet) {
            .wiredEthernet
        } else if path.usesInterfaceType(.cellular) {
            .cellular
        } else if path.usesInterfaceType(.loopback) {
            .loopback
        } else {
            .other
        }
        var address: String?
        if case .hostPort(let host, _) = path.remoteEndpoint {
            switch host {
            case .ipv4(let ipv4): address = "\(ipv4)"
            case .ipv6(let ipv6): address = "\(ipv6)"
            case .name(let name, _): address = name
            @unknown default: address = nil
            }
        }
        self.init(remoteAddress: address, interface: interface)
    }
}
