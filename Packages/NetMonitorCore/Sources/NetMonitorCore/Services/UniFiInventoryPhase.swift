import Foundation
import NetworkScanKit

public extension ScanPhaseID {
    static let unifiInventory = ScanPhaseID(rawValue: "unifiInventory")
}

/// Fills maker, model and name from the UniFi gateway's device list, for devices the scan
/// found. Needs a UniFi Network API key; without one it does nothing.
///
/// This reaches what nothing else can: UniFi devices on a fixed IP (no DNS name, no answer
/// to discovery) get their exact model, and every client's real MAC gives its maker even
/// where the system hides MACs from apps (macOS 27, iOS). A public MAC is recorded too: the
/// device match lets a saved device without a MAC adopt it (#461). A private MAC isn't: a
/// device without a MAC only adopts a private one when the names match, so recording it
/// could split a nameless device.
///
public struct UniFiInventoryPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .unifiInventory
    public let displayName = "Reading UniFi devices…"
    public let weight: Double = 0.02

    private let service: any UniFiNetworkServiceProtocol
    private let vendorForMAC: @Sendable (_ macAddress: String) async -> String?

    public init(
        service: any UniFiNetworkServiceProtocol = UniFiNetworkService(),
        vendorForMAC: (@Sendable (_ macAddress: String) async -> String?)? = nil
    ) {
        self.service = service
        if let vendorForMAC {
            self.vendorForMAC = vendorForMAC
        } else {
            let lookup = MACVendorLookupService()
            // The offline table only: an online lookup per client would stall the scan.
            self.vendorForMAC = { await lookup.lookup(macAddress: $0) }
        }
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        let entries = await service.inventory()
        guard !entries.isEmpty else {
            await onProgress(1.0)
            return
        }
        let found = await Set(accumulator.snapshot().map(\.ipAddress))
        var seen: Set<String> = []
        for entry in entries where found.contains(entry.ipAddress) && context.subnetFilter(entry.ipAddress) {
            guard seen.insert(entry.ipAddress).inserted else { continue } // the first entry per IP wins
            if let update = await update(for: entry) {
                await accumulator.upsert(update, confirmsPresence: false) // the scan already decided presence
            }
        }
        await onProgress(1.0)
    }

    /// Ranks (ADR-022, #462): the controller's model, a UniFi device's maker and the console's
    /// client name rank as UniFi; the maker from a client's MAC is a MAC-prefix maker (`vendor`);
    /// a maker or model parsed from UniFi's fingerprint name ("Meross Smart Bulb") is a guess.
    func update(for entry: UniFiInventoryEntry) async -> DiscoveredDevice? {
        let publicMAC = entry.macAddress.flatMap { mac in
            DeviceMatcher.normalizedMAC(mac).flatMap { MACAddress.isPrivate($0) ? nil : $0 }
        }
        var identity = DeviceIdentity(
            maker: entry.isUniFiDevice ? IdentityValue("Ubiquiti", source: .unifi) : nil,
            model: IdentityValue(entry.model, source: .unifi),
            friendlyName: IdentityValue(entry.name, source: .unifi)
        )
        var macPrefixMaker: String?
        if !entry.isUniFiDevice, let publicMAC {
            macPrefixMaker = await vendorForMAC(publicMAC)
        }
        if let name = entry.name, let guess = HostnameIdentity.parse(hostname: name) {
            let fill = guess.fills(knownMaker: identity.resolvedMaker(macPrefixMaker: macPrefixMaker), knownModel: identity.model?.value)
            identity = identity.merging(DeviceIdentity(
                maker: IdentityValue(fill.maker, source: .hostnameGuess),
                model: IdentityValue(fill.model, source: .hostnameGuess)
            ))
        }
        guard identity != DeviceIdentity() || macPrefixMaker != nil || publicMAC != nil else { return nil }
        return DiscoveredDevice(
            ipAddress: entry.ipAddress,
            hostname: nil,
            vendor: macPrefixMaker,
            macAddress: publicMAC,
            latency: nil,
            discoveredAt: Date(),
            source: .local,
            identity: identity
        )
    }
}
