import Foundation
import NetworkScanKit
import SwiftData

/// A device a plain-English rule can name, read through the identity seam (`LocalDevice.id`,
/// `displayName`, `deviceType`, maker) (#450). `DevicePhraseResolver` finds it from a phrase.
public struct RuleDevice: DevicePhraseMatchable, Sendable, Equatable, Identifiable, Hashable {
    public var id: UUID
    public var displayName: String
    public var deviceType: DeviceType
    public var maker: String?
    public var ipAddress: String
    /// The hardware address, when known.
    public var macAddress: String?
    /// Ports the device's last scan found open; an iOS monitoring target probes one (#572).
    public var openPorts: [Int]
    /// Every interface's row ID and address (#594): a target linked to, or checking, any of them
    /// checks this device. `id` and `ipAddress` alone for a device of one row.
    public var memberIDs: Set<UUID>
    public var addresses: Set<String>

    public init(
        id: UUID,
        displayName: String,
        deviceType: DeviceType,
        maker: String?,
        ipAddress: String,
        macAddress: String? = nil,
        openPorts: [Int] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.deviceType = deviceType
        self.maker = maker
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.openPorts = openPorts
        memberIDs = [id]
        addresses = [ipAddress]
    }

    /// A saved device as rules see it (#594: a device, not a row): the primary's stable identity
    /// (`LocalDevice.id`) and the identity seam's name, type and maker, the current member's
    /// address and every member's open ports. The maker leaves out model suggestions, as alert
    /// rules do (#449).
    public init(_ device: DeviceProjection) {
        let primary = device.primary
        self.init(
            id: primary.id,
            displayName: device.displayName,
            deviceType: primary.deviceType != .unknown ? primary.deviceType
                : device.members.first { $0.deviceType != .unknown }?.deviceType ?? .unknown,
            maker: primary.makerExcludingSuggestions ?? device.members.lazy.compactMap(\.makerExcludingSuggestions).first,
            ipAddress: device.ipAddress,
            macAddress: device.realMACs.first,
            openPorts: Set(device.members.flatMap { $0.openPorts ?? [] }).sorted()
        )
        memberIDs = device.memberIDs
        addresses = Set(device.members.map(\.ipAddress))
    }

    /// A device the latest scan saw but no saved row describes yet (#571), under a stand-in `id`
    /// until a draft saves its row. Its type comes from Core's device-type inference over what the
    /// scan knows (hostname, maker, open ports), so "the printer" can name it.
    public init(scanned device: DiscoveredDevice, id: UUID = UUID()) {
        // Unsaved: the inference reads a LocalDevice, and this one exists only to be read.
        let row = LocalDevice(
            ipAddress: device.ipAddress,
            macAddress: device.macAddress ?? "",
            hostname: device.hostname,
            vendor: device.vendor,
            openPorts: device.openPorts
        )
        row.mergeIdentity(device.identity)
        self.init(
            id: id,
            displayName: device.friendlyName ?? device.hostname ?? device.ipAddress,
            deviceType: DeviceTypeInferenceService().inferDeviceType(for: row),
            maker: device.maker,
            ipAddress: device.ipAddress,
            macAddress: device.macAddress.flatMap { $0.isEmpty ? nil : $0 },
            openPorts: device.openPorts ?? []
        )
    }
}

public extension RuleDevice {
    /// How many saved devices a described rule is resolved against.
    static let candidateLimit = 500

    /// The saved devices a described rule can name, shared by both apps: the network's when it is
    /// known (so the cap never drops them for another network's), else every network's; most
    /// recently seen first, capped at ``candidateLimit`` devices, each with all its members.
    static func candidates(network: UUID?, in context: ModelContext) -> [RuleDevice] {
        ((try? DeviceGroups.recentDevices(network: network, limit: candidateLimit, in: context)) ?? []).map(RuleDevice.init)
    }
}
