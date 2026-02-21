import Foundation

@MainActor
@Observable
public final class NetworkProfileManager {
    public private(set) var profiles: [NetworkProfile] = []
    public private(set) var activeProfile: NetworkProfile?

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
              let cidr = Self.parseCIDR(subnet) else {
            return nil
        }

        guard gatewayValue >= cidr.networkAddress, gatewayValue <= cidr.broadcastAddress else {
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

        if let index = profiles.firstIndex(where: {
            $0.id == detected.id ||
            ($0.isLocal && $0.discoveryMethod == .auto) ||
            $0.interfaceName == detected.interfaceName
        }) {
            let existing = profiles[index]
            detected.name = existing.name
            detected.lastScanned = existing.lastScanned
            detected.deviceCount = existing.deviceCount
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
    public nonisolated static func detectActiveProfiles() -> [NetworkProfile] {
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
            guard (flags & IFF_UP) != 0, (flags & IFF_RUNNING) != 0 else { continue }

            guard let network = NetworkUtilities.detectLocalIPv4Network(interface: name),
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
    public nonisolated static func primaryProfile() -> NetworkProfile? {
        detectActiveProfiles().first
    }

    // MARK: - Persistence

    private func loadProfiles() {
        guard let data = userDefaults.data(forKey: Self.storageKey) else { return }
        guard let decoded = try? JSONDecoder().decode([NetworkProfile].self, from: data) else { return }
        profiles = decoded
        activeProfile = Self.primaryProfile(from: decoded)
    }

    private func persistProfiles() {
        guard let encoded = try? JSONEncoder().encode(profiles) else { return }
        userDefaults.set(encoded, forKey: Self.storageKey)
    }

    // MARK: - Helpers

    private struct CIDRDescriptor {
        let networkAddress: UInt32
        let broadcastAddress: UInt32
        let netmask: UInt32
        let cidr: String
    }

    private nonisolated static func parseCIDR(_ value: String) -> CIDRDescriptor? {
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

    private nonisolated static func primaryProfile(from profiles: [NetworkProfile]) -> NetworkProfile? {
        profiles.first(where: { $0.isLocal }) ?? profiles.first
    }

    private nonisolated static func inferConnectionType(for interface: String) -> ConnectionType {
        switch interface {
        case "en0":
            return .wifi
        case "en1", "en2", "en3", "en4", "en5":
            return .ethernet
        default:
            if interface.hasPrefix("en") { return .ethernet }
            if interface.hasPrefix("pdp_ip") { return .cellular }
            return .ethernet
        }
    }

    private nonisolated static func sortPriority(_ profile: NetworkProfile) -> Int {
        switch profile.connectionType {
        case .wifi: return 0
        case .ethernet: return 1
        case .cellular: return 2
        case .none: return 3
        }
    }

    public func updateProfileScanInfo(id: UUID, lastScanned: Date, deviceCount: Int) {
        if let index = profiles.firstIndex(where: { $0.id == id }) {
            profiles[index].lastScanned = lastScanned
            profiles[index].deviceCount = deviceCount
            if activeProfile?.id == id {
                activeProfile = profiles[index]
            }
            persistProfiles()
        }
    }
}
