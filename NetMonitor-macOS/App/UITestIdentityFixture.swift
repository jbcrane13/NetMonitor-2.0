import Foundation
import NetMonitorCore

/// Network identification under `--uitesting` (#628 PR B). With `UITEST_IDENTITY=ask`, the local
/// network was identified by one router and the Mac now sees another, so the Devices screen asks
/// "Which network is this?" and its saved rows read as history. Otherwise no router hint is read,
/// so identification changes nothing. The store is a throwaway (`MacNetworkIdentity.Location`).
@MainActor
enum UITestIdentityFixture {
    static var asks: Bool {
        #if DEBUG
        ProcessInfo.processInfo.environment["UITEST_IDENTITY"] == "ask"
        #else
        false
        #endif
    }

    /// The fixture's local network, so the question names it and never the Mac's real network.
    nonisolated static let network = NetworkProfile(
        interfaceName: "en0", ipAddress: "192.168.77.10",
        network: NetworkUtilities.IPv4Network(
            networkAddress: 0xC0A8_4D00, broadcastAddress: 0xC0A8_4DFF, interfaceAddress: 0xC0A8_4D0A, netmask: 0xFFFF_FF00
        ),
        connectionType: .wifi, displayName: "Home office"
    )

    /// The profile manager's live networks: the fixture's with `UITEST_IDENTITY=ask`.
    static var activeProfilesProvider: @Sendable () -> [NetworkProfile] {
        guard asks else { return NetworkProfileManager.detectActiveProfiles }
        let fixture = network
        return { [fixture] }
    }

    static let homeKey = RouterKey(["uitest-home-router"])
    static let awayKey = RouterKey(["uitest-away-router"])

    static func readHint(_: String) -> RouterHintStatus {
        asks ? .present(awayKey) : .absent
    }

    /// Attaches identification for a UI-test launch, seeded as requested.
    static func attach(_ store: NetworkIdentityStore, discovery: DeviceDiscoveryCoordinator, profileManager: NetworkProfileManager) {
        seedIfRequested(store, local: profileManager.localProfile)
        MacNetworkIdentity.attach(store: store, discovery: discovery, profileManager: profileManager, readHint: readHint) { [weak profileManager] in
            profileManager?.detectLocalNetwork()
        }
    }

    /// Records the local network as identified by `homeKey`.
    static func seedIfRequested(_ store: NetworkIdentityStore, local: NetworkProfile?) {
        guard asks, let local else { return }
        let group = NetworkGroup(interface: local.interfaceName, subnet: local.subnet)
        try? store.update { contents in
            contents.records.removeAll { $0.group == group }
            contents.approvals.removeAll { $0.group == group }
            contents.records.append(IdentityRecord(id: local.id, group: group, recordClass: .bound))
            contents.approvals.append(IdentityApproval(group: group, key: homeKey, recordID: local.id))
        }
    }
}
