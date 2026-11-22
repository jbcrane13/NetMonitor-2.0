import Foundation

/// One device the UniFi gateway knows: a UniFi device it manages (with its exact model) or a
/// client connected to the network.
public struct UniFiInventoryEntry: Equatable, Sendable {
    public let ipAddress: String
    /// The name UniFi shows, without the MAC tail it appends ("Meross Smart Bulb 1f:57" →
    /// "Meross Smart Bulb"). Nil when the name was only a MAC.
    public let name: String?
    /// The product model, for UniFi devices only ("USW Pro Max 16 PoE", "U7 Pro").
    public let model: String?
    public let macAddress: String?
    public let isUniFiDevice: Bool

    public init(ipAddress: String, name: String?, model: String?, macAddress: String?, isUniFiDevice: Bool) {
        self.ipAddress = ipAddress
        self.name = name
        self.model = model
        self.macAddress = macAddress
        self.isUniFiDevice = isUniFiDevice
    }
}

/// Reads the device list from a UniFi gateway.
public protocol UniFiNetworkServiceProtocol: Sendable {
    /// Every UniFi device and connected client, or empty when the list can't be read.
    func inventory() async -> [UniFiInventoryEntry]
}

/// The UniFi gateway's device list. Reading it is off for now: `inventory()` returns nothing,
/// never reads a saved API key and sends no request. The parsers stay for when it returns.
public struct UniFiNetworkService: UniFiNetworkServiceProtocol {
    public init() {}

    public func inventory() async -> [UniFiInventoryEntry] {
        []
    }

    // MARK: - Parsing

    struct Page<Item: Decodable>: Decodable {
        let data: [Item]
        let totalCount: Int?
    }

    struct DeviceRecord: Decodable {
        let name: String?
        let model: String?
        let macAddress: String?
        let ipAddress: String?
    }

    struct ClientRecord: Decodable {
        let name: String?
        let macAddress: String?
        let ipAddress: String?
    }

    /// UniFi devices first, so a device listed as both keeps its model.
    static func entries(devices: [DeviceRecord], clients: [ClientRecord]) -> [UniFiInventoryEntry] {
        let fromDevices = devices.compactMap { device -> UniFiInventoryEntry? in
            guard let ip = device.ipAddress, !ip.isEmpty else { return nil }
            let model = device.model.flatMap { $0.isEmpty ? nil : $0 }
            return UniFiInventoryEntry(
                ipAddress: ip, name: cleanName(device.name), model: model,
                macAddress: device.macAddress, isUniFiDevice: true
            )
        }
        let fromClients = clients.compactMap { client -> UniFiInventoryEntry? in
            guard let ip = client.ipAddress, !ip.isEmpty else { return nil }
            return UniFiInventoryEntry(
                ipAddress: ip, name: cleanName(client.name), model: nil,
                macAddress: client.macAddress, isUniFiDevice: false
            )
        }
        return fromDevices + fromClients
    }

    /// Drops the "1f:57" MAC tail UniFi adds to generated names, and names that are only a MAC.
    static func cleanName(_ name: String?) -> String? {
        guard var name = name?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        if let range = name.range(of: #"\s+[0-9a-fA-F]{2}:[0-9a-fA-F]{2}$"#, options: .regularExpression) {
            name.removeSubrange(range)
        }
        if name.range(of: #"^([0-9a-fA-F]{2}[:-]){5}[0-9a-fA-F]{2}$"#, options: .regularExpression) != nil {
            return nil
        }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
