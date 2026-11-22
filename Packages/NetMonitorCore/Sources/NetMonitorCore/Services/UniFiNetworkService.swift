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

/// Reads UniFi devices and clients from the enrolled controller's UniFi Network integration API
/// (`/proxy/network/integration/v1`, Network 9.0 and later).
///
/// Only an enrolled controller is read, and only through `UniFiControllerTransport`, which sends
/// the key solely to that controller's verified HTTPS origin. Without an enrollment (including a
/// key saved by an earlier version without one) nothing is sent.
public struct UniFiNetworkService: UniFiNetworkServiceProtocol {
    private let enrollment: @Sendable () -> UniFiControllerEnrollment?
    private let transport: any UniFiControllerTransport

    public init(
        enrollment: @escaping @Sendable () -> UniFiControllerEnrollment? = { UniFiAPIKeyStore().enrollment() },
        transport: any UniFiControllerTransport = URLSessionUniFiTransport()
    ) {
        self.enrollment = enrollment
        self.transport = transport
    }

    public func inventory() async -> [UniFiInventoryEntry] {
        guard let enrollment = enrollment() else { return [] }
        let base = "https://\(enrollment.host)/proxy/network/integration/v1"
        guard let sitesData = await get("\(base)/sites", enrollment),
              let sites = try? JSONDecoder().decode(Page<Site>.self, from: sitesData) else { return [] }
        var entries: [UniFiInventoryEntry] = []
        for site in sites.data {
            let devices: [DeviceRecord] = await allPages("\(base)/sites/\(site.id)/devices", enrollment)
            let clients: [ClientRecord] = await allPages("\(base)/sites/\(site.id)/clients", enrollment)
            entries += Self.entries(devices: devices, clients: clients)
        }
        return entries
    }

    private func allPages<Item: Decodable>(_ url: String, _ enrollment: UniFiControllerEnrollment) async -> [Item] {
        let limit = 200
        var items: [Item] = []
        // A home network has a few hundred clients at most; ten pages is a safety stop.
        for page in 0..<10 {
            guard let data = await get("\(url)?offset=\(page * limit)&limit=\(limit)", enrollment),
                  let decoded = try? JSONDecoder().decode(Page<Item>.self, from: data) else { break }
            items += decoded.data
            if decoded.data.count < limit || items.count >= decoded.totalCount ?? 0 {
                break
            }
        }
        return items
    }

    private func get(_ url: String, _ enrollment: UniFiControllerEnrollment) async -> Data? {
        guard let url = URL(string: url) else { return nil }
        return await transport.get(url, enrollment: enrollment)
    }

    // MARK: - Parsing

    struct Page<Item: Decodable>: Decodable {
        let data: [Item]
        let totalCount: Int?
    }

    struct Site: Decodable {
        let id: String
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
