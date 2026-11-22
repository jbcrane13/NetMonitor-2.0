import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_macOS

/// #441: the dashboard's Gateway row shows the Mac's own network, not the last scanned one.
@MainActor
struct ConnectivityCardGatewayTests {
    @Test("Scanning a manual network leaves the Gateway row on the local gateway")
    func gatewayStaysLocal() throws {
        let suite = "ConnectivityCardGatewayTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let local = NetworkProfile(
            interfaceName: "en0",
            ipAddress: "192.168.1.10",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0xC0A80100, broadcastAddress: 0xC0A801FF,
                interfaceAddress: 0xC0A8010A, netmask: 0xFFFFFF00
            ),
            connectionType: .wifi,
            name: "Home",
            gatewayIP: "192.168.1.1",
            subnet: "192.168.1.0/24",
            isLocal: true,
            discoveryMethod: .auto
        )
        let manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [local] })
        let manual = try #require(manager.addProfile(gateway: "10.20.0.1", subnet: "10.20.0.0/24", name: "Office"))

        // DeviceDiscoveryCoordinator.scanNetwork switches to the scanned network.
        manager.switchProfile(id: manual.id)

        #expect(manager.activeProfile?.gatewayIP == "10.20.0.1")
        #expect(ConnectivityCard.gatewayText(manager) == "192.168.1.1")
        #expect(ConnectivityCard.gatewayText(nil) == "—")
    }
}
