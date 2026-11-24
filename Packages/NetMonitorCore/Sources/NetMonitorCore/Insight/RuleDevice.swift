import Foundation
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

    public init(id: UUID, displayName: String, deviceType: DeviceType, maker: String?, ipAddress: String, macAddress: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.deviceType = deviceType
        self.maker = maker
        self.ipAddress = ipAddress
        self.macAddress = macAddress
    }

    /// A saved device as rules see it: its stable identity and the identity seam's name, type and
    /// maker. The maker leaves out model suggestions, as alert rules do (#449).
    public init(_ device: LocalDevice) {
        self.init(
            id: device.id,
            displayName: device.displayName,
            deviceType: device.deviceType,
            maker: device.makerExcludingSuggestions,
            ipAddress: device.ipAddress,
            macAddress: device.macAddress.isEmpty ? nil : device.macAddress
        )
    }
}

public extension RuleDevice {
    /// How many saved devices a described rule is resolved against.
    static let candidateLimit = 500

    /// The saved devices a described rule can name, shared by both apps: the network's when it is
    /// known (so the cap never drops them for another network's), else every network's; most
    /// recently seen first, capped at ``candidateLimit``.
    static func candidates(network: UUID?) -> FetchDescriptor<LocalDevice> {
        var descriptor: FetchDescriptor<LocalDevice>
        if let network {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.networkProfileID == network })
        } else {
            descriptor = FetchDescriptor()
        }
        descriptor.sortBy = [SortDescriptor(\.lastSeen, order: .reverse)]
        descriptor.fetchLimit = candidateLimit
        return descriptor
    }
}
