import Foundation
import NetMonitorCore

/// Network identification under `--uitesting` (#628 PR B), by `UITEST_IDENTITY`:
/// - `ask`: the fixture network ("Home office") was identified by one router and the Mac now sees
///   another, so the Devices screen asks "Which network is this?" and its saved rows read as history;
/// - `legacy`: the fixture network is known only from before identification, and the identification
///   probe can't clearly match it (the fixture scan has no gateway row), so it asks "Is this …?";
/// - `live`: the real network and the real router hint, to check the reader in the signed app; its
///   status is logged as a kind only (`networkIdentity` category);
/// - unset: no router hint is read, so identification changes nothing.
///
/// The store and its defaults are throwaways (`MacNetworkIdentity.Location`).
@MainActor
enum UITestIdentityFixture {
    enum Mode: String {
        case ask, legacy, live
    }

    static var mode: Mode? {
        #if DEBUG
        ProcessInfo.processInfo.environment["UITEST_IDENTITY"].flatMap(Mode.init(rawValue:))
        #else
        nil
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

    /// The profile manager's live networks: the fixture's for `ask` and `legacy`.
    static var activeProfilesProvider: @Sendable () -> [NetworkProfile] {
        guard mode == .ask || mode == .legacy else { return NetworkProfileManager.detectActiveProfiles }
        let fixture = network
        return { [fixture] }
    }

    static let homeKey = RouterKey(["uitest-home-router"])
    static let awayKey = RouterKey(["uitest-away-router"])

    static func readHint(_ interface: String) -> RouterHintStatus {
        switch mode {
        case .ask, .legacy: .present(awayKey)
        case .live: RouterHint.read(interface: interface)
        case nil: .absent
        }
    }

    /// Attaches identification for a UI-test launch, seeded as requested.
    static func attach(_ store: NetworkIdentityStore, discovery: DeviceDiscoveryCoordinator, profileManager: NetworkProfileManager) {
        seedIfRequested(store, local: profileManager.localProfile)
        MacNetworkIdentity.attach(store: store, discovery: discovery, profileManager: profileManager, readHint: readHint) { [weak profileManager] in
            profileManager?.detectLocalNetwork()
        }
    }

    /// `ask`: the local network identified by `homeKey`. `legacy`: known only from the v1 map.
    static func seedIfRequested(_ store: NetworkIdentityStore, local: NetworkProfile?) {
        guard let mode, mode != .live, let local else { return }
        let group = NetworkGroup(interface: local.interfaceName, subnet: local.subnet)
        try? store.update { contents in
            contents.records.removeAll { $0.group == group }
            contents.approvals.removeAll { $0.group == group }
            if mode == .ask {
                contents.records.append(IdentityRecord(id: local.id, group: group, recordClass: .bound))
                contents.approvals.append(IdentityApproval(group: group, key: homeKey, recordID: local.id))
            } else {
                contents.records.append(IdentityRecord(id: local.id, group: group, recordClass: .legacyUnverified))
                if !contents.legacyIDs.contains(local.id) {
                    contents.legacyIDs.append(local.id)
                }
            }
        }
    }
}
