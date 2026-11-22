import Foundation

@MainActor
@Observable
public final class NetworkProfileManager {
    public private(set) var profiles: [NetworkProfile] = []
    /// The last network switched to, which is the last one scanned. Scanning a manual network
    /// makes it active, so this isn't the network this device is on; that's ``localProfile``.
    public private(set) var activeProfile: NetworkProfile?

    /// The network this device is on: the auto-detected local network (#441).
    public var localProfile: NetworkProfile? {
        profiles.first { $0.isLocal && $0.discoveryMethod == .auto } ?? profiles.first(where: \.isLocal)
    }

    private let userDefaults: UserDefaults
    private let activeProfilesProvider: @Sendable () -> [NetworkProfile]

    private static let storageKey = "netmonitor.networkProfiles"

    public init(
        userDefaults: UserDefaults = .standard,
        activeProfilesProvider: @escaping @Sendable () -> [NetworkProfile] = NetworkProfileManager.detectActiveProfiles
    ) {
        self.userDefaults = userDefaults
        self.activeProfilesProvider = activeProfilesProvider

        loadProfiles()
        detectLocalNetwork()

        if activeProfile == nil {
            activeProfile = Self.primaryProfile(from: profiles) ?? profiles.first
        }
    }

    @discardableResult
    public func addProfile(gateway: String, subnet: String, name: String) -> NetworkProfile? {
        guard let gatewayValue = NetworkUtilities.ipv4ToUInt32(gateway),
              let cidr = Self.parseCIDR(subnet),
              gatewayValue >= cidr.networkAddress, gatewayValue <= cidr.broadcastAddress else {
            return nil
        }

        let network = NetworkUtilities.IPv4Network(
            networkAddress: cidr.networkAddress,
            broadcastAddress: cidr.broadcastAddress,
            interfaceAddress: gatewayValue,
            netmask: cidr.netmask
        )
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? "Network \(cidr.cidr)" : trimmedName

        if let existingIndex = profiles.firstIndex(where: {
            $0.gatewayIP == gateway && $0.subnet == cidr.cidr
        }) {
            var existing = profiles[existingIndex]
            // Never demote this device's auto-detected network to a manual one.
            if existing.isLocal && existing.discoveryMethod == .auto {
                return existing
            }
            existing.name = resolvedName
            existing.ipAddress = gateway
            existing.network = network
            existing.gatewayIP = gateway
            existing.subnet = cidr.cidr
            existing.isLocal = false
            existing.discoveryMethod = .manual
            if existing.interfaceName.isEmpty {
                existing.interfaceName = "manual-\(gateway)"
            }

            profiles[existingIndex] = existing
            if activeProfile?.id == existing.id {
                activeProfile = existing
            }
            persistProfiles()
            return existing
        }

        let profile = NetworkProfile(
            id: UUID(),
            interfaceName: "manual-\(gateway)",
            ipAddress: gateway,
            network: network,
            connectionType: .ethernet,
            name: resolvedName,
            gatewayIP: gateway,
            subnet: cidr.cidr,
            isLocal: false,
            discoveryMethod: .manual
        )
        profiles.append(profile)

        if activeProfile == nil {
            activeProfile = profile
        }

        persistProfiles()
        return profile
    }

    /// Adds or updates a profile discovered via companion handshake.
    @discardableResult
    public func upsertCompanionProfile(
        gateway: String,
        subnet: String,
        name: String,
        interfaceName: String? = nil
    ) -> NetworkProfile? {
        guard let gatewayValue = NetworkUtilities.ipv4ToUInt32(gateway),
              let cidr = Self.parseCIDR(subnet),
              gatewayValue >= cidr.networkAddress, gatewayValue <= cidr.broadcastAddress else {
            return nil
        }

        let normalizedInterface = interfaceName?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let resolvedInterface = (normalizedInterface?.isEmpty == false)
            ? normalizedInterface!
            : "companion-\(gateway)"
        let resolvedName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Companion \(cidr.cidr)"
            : name.trimmingCharacters(in: .whitespacesAndNewlines)

        let network = NetworkUtilities.IPv4Network(
            networkAddress: cidr.networkAddress,
            broadcastAddress: cidr.broadcastAddress,
            interfaceAddress: gatewayValue,
            netmask: cidr.netmask
        )
        let connectionType = Self.inferConnectionType(for: resolvedInterface)

        // The companion is on the same network as this device: keep the local profile as-is.
        if let local = profiles.first(where: {
            $0.isLocal && $0.discoveryMethod == .auto && $0.gatewayIP == gateway && $0.subnet == cidr.cidr
        }) {
            return local
        }

        if let existingIndex = profiles.firstIndex(where: {
            ($0.gatewayIP == gateway && $0.subnet == cidr.cidr) ||
            ($0.discoveryMethod == .companion && $0.interfaceName == resolvedInterface)
        }) {
            var existing = profiles[existingIndex]
            existing.name = resolvedName
            existing.interfaceName = resolvedInterface
            existing.ipAddress = gateway
            existing.network = network
            existing.connectionType = connectionType
            existing.gatewayIP = gateway
            existing.subnet = cidr.cidr
            existing.isLocal = false
            existing.discoveryMethod = .companion
            profiles[existingIndex] = existing

            if activeProfile?.id == existing.id {
                activeProfile = existing
            }

            persistProfiles()
            return existing
        }

        let profile = NetworkProfile(
            id: UUID(),
            interfaceName: resolvedInterface,
            ipAddress: gateway,
            network: network,
            connectionType: connectionType,
            name: resolvedName,
            gatewayIP: gateway,
            subnet: cidr.cidr,
            isLocal: false,
            discoveryMethod: .companion
        )
        profiles.append(profile)

        if activeProfile == nil {
            activeProfile = profile
        }

        persistProfiles()
        return profile
    }

    @discardableResult
    public func removeProfile(id: UUID) -> Bool {
        guard let index = profiles.firstIndex(where: { $0.id == id }) else {
            return false
        }

        let profile = profiles[index]
        guard !(profile.isLocal && profile.discoveryMethod == .auto) else {
            return false
        }

        profiles.remove(at: index)

        if activeProfile?.id == id {
            activeProfile = Self.primaryProfile(from: profiles) ?? profiles.first
        }

        persistProfiles()
        return true
    }

    @discardableResult
    public func switchProfile(id: UUID) -> Bool {
        guard let profile = profiles.first(where: { $0.id == id }) else {
            return false
        }

        activeProfile = profile
        return true
    }

    public func detectLocalNetwork() {
        guard var detected = activeProfilesProvider().first else {
            if activeProfile == nil {
                activeProfile = profiles.first
            }
            return
        }

        detected.isLocal = true
        detected.discoveryMethod = .auto
        // Each network the device joins gets its own id, so devices found on one network
        // are never listed, merged or cached under another one on the same interface.
        let networkID = resolveLocalNetworkID(for: detected)
        if networkID != detected.id {
            detected = detected.withID(networkID)
        }

        if let index = profiles.firstIndex(where: {
            $0.id == detected.id ||
            ($0.isLocal && $0.discoveryMethod == .auto) ||
            $0.interfaceName == detected.interfaceName
        }) {
            let existing = profiles[index]
            // The name is always regenerated: neither app can rename a detected network, and
            // a new subnet on the same interface must not keep the old network's name (#359).
            if existing.subnet == detected.subnet {
                detected.lastScanned = existing.lastScanned
                detected.deviceCount = existing.deviceCount
            }
            profiles[index] = detected
        } else {
            profiles.append(detected)
        }

        profiles.removeAll { profile in
            profile.id != detected.id && profile.isLocal && profile.discoveryMethod == .auto
        }

        if activeProfile?.id == detected.id || activeProfile == nil {
            activeProfile = detected
        } else if let activeID = activeProfile?.id,
                  !profiles.contains(where: { $0.id == activeID }) {
            activeProfile = detected
        }

        persistProfiles()
    }

    // MARK: - Static Interface Enumeration

    /// Returns all active IPv4 network interfaces, sorted by priority
    /// (Wi-Fi first, then Ethernet, then others).
    ///
    /// Filters out:
    /// - Loopback (lo0)
    /// - Link-local addresses (169.254.x.x)
    /// - Interfaces that are not UP and RUNNING
    /// - Duplicate interface entries
    nonisolated public static func detectActiveProfiles() -> [NetworkProfile] {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let firstAddr = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        var profiles: [NetworkProfile] = []
        var seen = Set<String>()

        for ptr in sequence(first: firstAddr, next: { $0.pointee.ifa_next }) {
            let iface = ptr.pointee

            guard let address = iface.ifa_addr, address.pointee.sa_family == UInt8(AF_INET) else { continue }

            let name = String(cString: iface.ifa_name)
            guard name != "lo0", !seen.contains(name) else { continue }

            let flags = Int32(iface.ifa_flags)
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0,
                  let network = NetworkUtilities.detectLocalIPv4Network(interface: name),
                  let ip = NetworkUtilities.detectLocalIPAddress(interface: name) else { continue }

            // Skip link-local (APIPA) addresses
            guard !ip.hasPrefix("169.254.") else { continue }

            let connectionType = inferConnectionType(for: name)

            profiles.append(NetworkProfile(
                interfaceName: name,
                ipAddress: ip,
                network: network,
                connectionType: connectionType
            ))
            seen.insert(name)
        }

        return profiles.sorted { sortPriority($0) < sortPriority($1) }
    }

    /// Returns the "primary" profile — the first active interface by priority,
    /// or nil if no interfaces are active.
    nonisolated public static func primaryProfile() -> NetworkProfile? {
        detectActiveProfiles().first
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard let data = userDefaults.data(forKey: Self.storageKey), let decoded = try? JSONDecoder().decode([NetworkProfile].self, from: data) else { return }
        profiles = decoded
        activeProfile = Self.primaryProfile(from: decoded)
    }

    private func persistProfiles() {
        guard let encoded = try? JSONEncoder().encode(profiles) else { return }
        userDefaults.set(encoded, forKey: Self.storageKey)
    }

    // MARK: - Per-network ids

    /// "interface|subnet" → profile id, for every local network this device has been on.
    private static let knownLocalNetworksKey = "netmonitor.knownLocalNetworkIDs"

    nonisolated static func localNetworkKey(interface: String, subnet: String) -> String {
        "\(interface)|\(subnet)"
    }

    /// The id the detected network goes by. Before this, a detected network's id was its
    /// interface's `stableID`, so the home network and any other Wi-Fi shared one id and
    /// each one showed the other's devices. Now:
    /// - a network seen before keeps the id it had, so its devices come back;
    /// - the first network seen on an interface keeps the interface's `stableID`, which is
    ///   what every existing install already stored its devices under;
    /// - any other network on that interface gets an id derived from interface and subnet.
    /// Read from and written to `userDefaults` on every call, because each view model owns
    /// its own manager and they must all agree on the id.
    private func resolveLocalNetworkID(for detected: NetworkProfile) -> UUID {
        let stored = userDefaults.dictionary(forKey: Self.knownLocalNetworksKey) as? [String: String] ?? [:]
        var known = stored.compactMapValues(UUID.init(uuidString:))
        let before = known

        // Seed with the local profile persisted before this map existed, so an update keeps
        // the current network's devices under the id they were saved with.
        for profile in profiles where profile.isLocal && profile.discoveryMethod == .auto {
            let key = Self.localNetworkKey(interface: profile.interfaceName, subnet: profile.subnet)
            if known[key] == nil, !known.values.contains(profile.id) {
                known[key] = profile.id
            }
        }

        let key = Self.localNetworkKey(interface: detected.interfaceName, subnet: detected.subnet)
        let id: UUID
        if let existing = known[key] {
            id = existing
        } else if known.values.contains(detected.id) {
            id = NetworkProfile.networkID(forKey: key)
            known[key] = id
        } else {
            id = detected.id
            known[key] = id
        }

        if known != before {
            userDefaults.set(known.mapValues(\.uuidString), forKey: Self.knownLocalNetworksKey)
        }
        return id
    }

    // MARK: - Helpers

    private struct CIDRDescriptor {
        let networkAddress: UInt32
        let broadcastAddress: UInt32
        let netmask: UInt32
        let cidr: String
    }

    nonisolated private static func parseCIDR(_ value: String) -> CIDRDescriptor? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/")
        guard parts.count == 2,
              let networkAddress = NetworkUtilities.ipv4ToUInt32(String(parts[0])),
              let prefixLength = Int(parts[1]),
              prefixLength >= 0,
              prefixLength <= 32 else {
            return nil
        }

        let netmask: UInt32
        if prefixLength == 0 {
            netmask = 0
        } else {
            netmask = UInt32.max << UInt32(32 - prefixLength)
        }

        let normalizedNetwork = networkAddress & netmask
        let broadcastAddress = normalizedNetwork | ~netmask
        let cidr = "\(NetworkUtilities.uint32ToIPv4(normalizedNetwork))/\(prefixLength)"

        return CIDRDescriptor(
            networkAddress: normalizedNetwork,
            broadcastAddress: broadcastAddress,
            netmask: netmask,
            cidr: cidr
        )
    }

    nonisolated private static func primaryProfile(from profiles: [NetworkProfile]) -> NetworkProfile? {
        profiles.first(where: { $0.isLocal }) ?? profiles.first
    }

    nonisolated private static func inferConnectionType(for interface: String) -> ConnectionType {
        switch interface {
        case "en0":
            return .wifi
        case "en1", "en2", "en3", "en4", "en5":
            return .ethernet
        default:
            if interface.hasPrefix("en") {
                return .ethernet
            }
            if interface.hasPrefix("pdp_ip") {
                return .cellular
            }
            return .ethernet
        }
    }

    nonisolated private static func sortPriority(_ profile: NetworkProfile) -> Int {
        switch profile.connectionType {
        case .wifi: return 0
        case .ethernet: return 1
        case .cellular: return 2
        case .none: return 3
        }
    }

    public func updateProfileScanInfo(
        id: UUID,
        lastScanned: Date,
        deviceCount: Int,
        gatewayReachable: Bool? = nil
    ) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].lastScanned = lastScanned
            profiles[index].deviceCount = deviceCount
            if let gatewayReachable {
                profiles[index].gatewayReachable = gatewayReachable
            }
            if activeProfile?.id == id {
                activeProfile = profiles[index]
            }
            persistProfiles()
        }
    }
}
