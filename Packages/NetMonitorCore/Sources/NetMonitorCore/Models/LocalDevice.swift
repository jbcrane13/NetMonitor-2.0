import Foundation
import NetworkScanKit
import SwiftData

/// A locally-discovered network device, persisted via SwiftData.
/// This is the iOS-derived model (richer than the macOS equivalent).
@Model
public final class LocalDevice {
    @Attribute(.unique) public var id: UUID
    public var ipAddress: String
    public var macAddress: String
    public var hostname: String?
    public var vendor: String?
    public var deviceType: DeviceType
    public var customName: String?
    public var status: DeviceStatus
    public var lastLatency: Double?
    public var isGateway: Bool = false
    public var supportsWakeOnLan: Bool = false
    public var firstSeen: Date
    public var lastSeen: Date
    public var notes: String?
    public var resolvedHostname: String?
    /// The maker the device announced (UPnP, UniFi, Bonjour) or a guess from its names;
    /// `vendor` is the MAC-prefix maker only. Views show ``maker``, the higher-ranked of the
    /// two (ADR-022).
    public var manufacturer: String?
    public var openPorts: [Int]?
    public var discoveredServices: [String]?
    public var networkProfileID: UUID?
    /// Exact model from Bonjour TXT records (#386, e.g. `MacBookPro18,1`) or the UPnP
    /// description (#387), refreshed by each scan. Stored since macOS `SchemaV2` (#409);
    /// iOS migrates its unversioned store automatically (an added optional attribute).
    public var modelName: String?
    /// Where `modelName`, `manufacturer` and `friendlyName` came from: ``IdentitySource``
    /// raw values. Nil (a value saved before macOS `SchemaV3`) ranks below every source.
    public var modelSource: String?
    public var makerSource: String?
    public var friendlyNameSource: String?
    /// The name the device or the UniFi console gives it. Before `SchemaV3` it was written
    /// into `hostname`; now it's kept apart and ranked (UniFi > UPnP).
    public var friendlyName: String?

    /// In-memory buffer of recent latency readings for sparkline display.
    /// Not persisted — resets each session. Capped at 20 samples.
    @Transient public var latencyHistory: [Double] = []

    /// Maximum number of latency samples to retain in memory.
    private static let maxLatencyHistory = 20

    public init(
        id: UUID = UUID(),
        ipAddress: String,
        macAddress: String,
        hostname: String? = nil,
        vendor: String? = nil,
        deviceType: DeviceType = .unknown,
        customName: String? = nil,
        status: DeviceStatus = .online,
        lastLatency: Double? = nil,
        isGateway: Bool = false,
        supportsWakeOnLan: Bool = false,
        notes: String? = nil,
        resolvedHostname: String? = nil,
        manufacturer: String? = nil,
        openPorts: [Int]? = nil,
        discoveredServices: [String]? = nil,
        networkProfileID: UUID? = nil
    ) {
        self.id = id
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.hostname = hostname
        self.vendor = vendor
        self.deviceType = deviceType
        self.customName = customName
        self.status = status
        self.lastLatency = lastLatency
        self.isGateway = isGateway
        self.supportsWakeOnLan = supportsWakeOnLan
        self.firstSeen = Date()
        self.lastSeen = Date()
        self.notes = notes
        self.resolvedHostname = resolvedHostname
        self.manufacturer = manufacturer
        self.openPorts = openPorts
        self.discoveredServices = discoveredServices
        self.networkProfileID = networkProfileID
    }

    /// The device name: the custom name, else the friendly name, else a hostname, else the IP.
    public var displayName: String {
        customName ?? friendlyName ?? resolvedHostname ?? hostname ?? ipAddress
    }

    /// The name the device match compares: the hostname, else the friendly name (see
    /// `DiscoveredDevice.matchName`).
    public var matchName: String? {
        [hostname, friendlyName].compactMap { $0 }.first { !$0.isEmpty }
    }

    /// The stored maker, model and friendly name with their sources (ADR-022).
    public var identity: DeviceIdentity {
        get {
            DeviceIdentity(
                maker: IdentityValue(manufacturer, source: makerSource.flatMap(IdentitySource.init(rawValue:))),
                model: IdentityValue(modelName, source: modelSource.flatMap(IdentitySource.init(rawValue:))),
                friendlyName: IdentityValue(friendlyName, source: friendlyNameSource.flatMap(IdentitySource.init(rawValue:)))
            )
        }
        set {
            manufacturer = newValue.maker?.value
            makerSource = newValue.maker?.source?.rawValue
            modelName = newValue.model?.value
            modelSource = newValue.model?.source?.rawValue
            friendlyName = newValue.friendlyName?.value
            friendlyNameSource = newValue.friendlyName?.source?.rawValue
        }
    }

    /// Merges a scan's identity into the saved one by rank (ADR-022). Writes only on change.
    public func mergeIdentity(_ scanned: DeviceIdentity) {
        let merged = identity.merging(scanned)
        if merged != identity {
            identity = merged
        }
    }

    /// The maker to show: the announced or guessed maker, or the MAC-prefix maker, whichever
    /// ranks higher (ADR-022).
    public var maker: String? {
        identity.resolvedMaker(macPrefixMaker: vendor)
    }

    /// ``maker`` without a model suggestion (#449): for alert rules and the companion feed,
    /// which act on what the device and the user said, not on a guess.
    public var makerExcludingSuggestions: String? {
        identity.withoutSuggestions.resolvedMaker(macPrefixMaker: vendor)
    }

    public var formattedMacAddress: String {
        macAddress.uppercased()
    }

    public var latencyText: String? {
        guard let latency = lastLatency else { return nil }
        if latency < 1 {
            return "<1 ms"
        }
        return String(format: "%.0f ms", latency)
    }

    public func updateStatus(to newStatus: DeviceStatus) {
        status = newStatus
        lastSeen = Date()
    }

    public func updateLatency(_ latency: Double) {
        lastLatency = latency
        lastSeen = Date()
        if status == .offline || status == .cached {
            status = .online
        }
        // Append to in-memory sparkline buffer
        latencyHistory.append(latency)
        if latencyHistory.count > Self.maxLatencyHistory {
            latencyHistory.removeFirst(latencyHistory.count - Self.maxLatencyHistory)
        }
    }
}
