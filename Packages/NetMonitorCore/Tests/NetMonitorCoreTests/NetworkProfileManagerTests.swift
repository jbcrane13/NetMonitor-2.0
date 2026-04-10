import Foundation
import Testing
@testable import NetMonitorCore

struct NetworkProfileManagerTests {
    @Test("Profile CRUD: add, switch, remove")
    @MainActor
    func profileCRUD() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { clear(defaults, suiteName: suiteName) }

        let localProfile = makeProfile(
            interfaceName: "en0",
            ipAddress: "192.168.1.10",
            connectionType: .wifi,
            subnet: "192.168.1.0/24"
        )
        let manager = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [localProfile] in [localProfile] }
        )

        let added = manager.addProfile(gateway: "10.0.0.1", subnet: "10.0.0.0/24", name: "Lab")
        #expect(added != nil)
        guard let added else { return }

        #expect(manager.profiles.contains(where: { $0.id == added.id }))
        #expect(manager.switchProfile(id: added.id))
        #expect(manager.activeProfile?.id == added.id)

        #expect(manager.removeProfile(id: added.id))
        #expect(!manager.profiles.contains(where: { $0.id == added.id }))
    }

    @Test("Persistence: profiles are saved and reloaded")
    @MainActor
    func persistenceRoundTrip() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { clear(defaults, suiteName: suiteName) }

        let localProfile = makeProfile(
            interfaceName: "en0",
            ipAddress: "192.168.1.20",
            connectionType: .wifi,
            subnet: "192.168.1.0/24"
        )
        let managerA = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [localProfile] in [localProfile] }
        )
        let added = managerA.addProfile(gateway: "10.1.0.1", subnet: "10.1.0.0/24", name: "Office")
        #expect(added != nil)

        let managerB = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [localProfile] in [localProfile] }
        )

        let containsOffice = managerB.profiles.contains { profile in
            profile.gatewayIP == "10.1.0.1" &&
            profile.subnet == "10.1.0.0/24" &&
            profile.name == "Office"
        }
        #expect(containsOffice)
    }

    @Test("Local network detection creates/updates a local profile")
    @MainActor
    func localNetworkDetection() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { clear(defaults, suiteName: suiteName) }

        let localProfile = makeProfile(
            interfaceName: "en0",
            ipAddress: "172.16.1.25",
            connectionType: .wifi,
            subnet: "172.16.1.0/24"
        )
        let manager = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [localProfile] in [localProfile] }
        )

        manager.detectLocalNetwork()

        let detectedLocal = manager.profiles.first(where: { $0.isLocal && $0.discoveryMethod == .auto })
        #expect(detectedLocal?.interfaceName == "en0")
        #expect(detectedLocal?.subnet == "172.16.1.0/24")
    }

    @Test("Cannot remove local auto-detected profile")
    @MainActor
    func cannotRemoveLocalProfile() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { clear(defaults, suiteName: suiteName) }

        let localProfile = makeProfile(
            interfaceName: "en0",
            ipAddress: "192.168.50.10",
            connectionType: .wifi,
            subnet: "192.168.50.0/24"
        )
        let manager = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [localProfile] in [localProfile] }
        )

        guard let localID = manager.profiles.first(where: { $0.isLocal })?.id else {
            Issue.record("Expected a local profile to be present")
            return
        }
        #expect(manager.removeProfile(id: localID) == false)
    }

    @Test("Active profile defaults to primary profile")
    @MainActor
    func activeProfileDefaultsToPrimary() throws {
        let (defaults, suiteName) = makeUserDefaults()
        defer { clear(defaults, suiteName: suiteName) }

        let remoteProfile = makeProfile(
            interfaceName: "manual-10.10.0.1",
            ipAddress: "10.10.0.1",
            connectionType: .ethernet,
            subnet: "10.10.0.0/24",
            isLocal: false,
            discoveryMethod: .manual
        )
        let localProfile = makeProfile(
            interfaceName: "en0",
            ipAddress: "192.168.77.15",
            connectionType: .wifi,
            subnet: "192.168.77.0/24",
            isLocal: true,
            discoveryMethod: .auto
        )
        let seededProfiles = [remoteProfile, localProfile]
        let data = try JSONEncoder().encode(seededProfiles)
        defaults.set(data, forKey: "netmonitor.networkProfiles")

        let manager = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [] }
        )
        #expect(manager.activeProfile?.id == localProfile.id)
    }

    @Test("Companion sync upserts companion profile")
    @MainActor
    func companionProfileUpsert() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { clear(defaults, suiteName: suiteName) }

        let localProfile = makeProfile(
            interfaceName: "en0",
            ipAddress: "192.168.1.10",
            connectionType: .wifi,
            subnet: "192.168.1.0/24"
        )
        let manager = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [localProfile] in [localProfile] }
        )

        let first = manager.upsertCompanionProfile(
            gateway: "10.0.0.1",
            subnet: "10.0.0.0/24",
            name: "Office Network",
            interfaceName: "en5"
        )
        #expect(first != nil)
        #expect(first?.discoveryMethod == .companion)
        #expect(first?.isLocal == false)

        let second = manager.upsertCompanionProfile(
            gateway: "10.0.0.1",
            subnet: "10.0.0.0/24",
            name: "Office Network Updated",
            interfaceName: "en5"
        )
        #expect(second?.id == first?.id)
        #expect(manager.profiles.filter { $0.discoveryMethod == .companion }.count == 1)
        #expect(manager.profiles.first(where: { $0.id == second?.id })?.name == "Office Network Updated")
    }

    @Test("Integration: local and remote scan metadata stay separated")
    @MainActor
    func scanMetadataSeparationAcrossProfiles() {
        let (defaults, suiteName) = makeUserDefaults()
        defer { clear(defaults, suiteName: suiteName) }

        let localProfile = makeProfile(
            interfaceName: "en0",
            ipAddress: "192.168.1.25",
            connectionType: .wifi,
            subnet: "192.168.1.0/24"
        )
        let manager = NetworkProfileManager(
            userDefaults: defaults,
            activeProfilesProvider: { [localProfile] in [localProfile] }
        )
        let remote = manager.addProfile(gateway: "10.20.0.1", subnet: "10.20.0.0/24", name: "Remote Lab")
        #expect(remote != nil)
        guard let remote else { return }

        let localDate = Date().addingTimeInterval(-120)
        let remoteDate = Date()
        manager.updateProfileScanInfo(
            id: localProfile.id,
            lastScanned: localDate,
            deviceCount: 12,
            gatewayReachable: true
        )
        manager.updateProfileScanInfo(
            id: remote.id,
            lastScanned: remoteDate,
            deviceCount: 3,
            gatewayReachable: false
        )

        let updatedLocal = manager.profiles.first(where: { $0.id == localProfile.id })
        let updatedRemote = manager.profiles.first(where: { $0.id == remote.id })
        #expect(updatedLocal?.deviceCount == 12)
        #expect(updatedLocal?.gatewayReachable == true)
        #expect(updatedRemote?.deviceCount == 3)
        #expect(updatedRemote?.gatewayReachable == false)
        #expect(updatedLocal?.subnet != updatedRemote?.subnet)
    }

    // MARK: - Helpers

    private func makeUserDefaults() -> (UserDefaults, String) {
        let suite = "NetworkProfileManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }

    private func clear(_ defaults: UserDefaults, suiteName: String) {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeProfile(
        interfaceName: String,
        ipAddress: String,
        connectionType: ConnectionType,
        subnet: String,
        isLocal: Bool = true,
        discoveryMethod: DiscoveryMethod = .auto
    ) -> NetworkProfile {
        let network = makeNetwork(subnet)
        return NetworkProfile(
            id: NetworkProfile.stableID(for: interfaceName),
            interfaceName: interfaceName,
            ipAddress: ipAddress,
            network: network,
            connectionType: connectionType,
            name: "\(connectionType.displayName) - \(subnet)",
            gatewayIP: gateway(for: subnet),
            subnet: subnet,
            isLocal: isLocal,
            discoveryMethod: discoveryMethod
        )
    }

    private func makeNetwork(_ cidr: String) -> NetworkUtilities.IPv4Network {
        let parts = cidr.split(separator: "/")
        let ip = String(parts[0])
        let prefix = Int(parts[1]) ?? 24

        let rawAddress = NetworkUtilities.ipv4ToUInt32(ip) ?? 0
        let netmask: UInt32 = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
        let networkAddress = rawAddress & netmask
        let broadcastAddress = networkAddress | ~netmask
        let interfaceAddress = networkAddress &+ 2

        return NetworkUtilities.IPv4Network(
            networkAddress: networkAddress,
            broadcastAddress: broadcastAddress,
            interfaceAddress: interfaceAddress,
            netmask: netmask
        )
    }

    private func gateway(for cidr: String) -> String {
        let parts = cidr.split(separator: "/")
        let ip = String(parts[0])
        guard let rawAddress = NetworkUtilities.ipv4ToUInt32(ip) else { return ip }
        return NetworkUtilities.uint32ToIPv4(rawAddress &+ 1)
    }
}
