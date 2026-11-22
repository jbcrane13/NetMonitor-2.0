import Foundation

/// Guesses an empty maker and model from each device's names (#439), for example a switch
/// named `unifi-pro-max-16-switch` becomes Ubiquiti, "UniFi Pro Max 16 Switch".
///
/// A device can carry a Bonjour name, a UPnP name and a DNS name. The accumulator keeps the
/// first name it hears, so a Bonjour name like `12A9007389F1@Living room` hides a DNS name
/// like `u7-pro.lan`. The phase reads the hostname, then the UPnP name, then, when neither
/// identifies the device, asks `lookUpName` for its DNS name.
///
/// Guesses are ``IdentitySource/hostnameGuess``, the lowest rank, so where the phase runs
/// doesn't decide what wins (ADR-022). It runs last in the standard pipeline only so it can
/// read the names every other step found.
public struct HostnameIdentityPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .hostnameIdentity
    public let displayName = "Reading device names…"
    public let weight: Double = 0.01

    /// Returns a DNS name for an IP, or nil. Nil skips the lookup.
    private let lookUpName: (@Sendable (_ ipAddress: String) async -> String?)?
    private let maxConcurrentLookups: Int

    public init(lookUpName: (@Sendable (_ ipAddress: String) async -> String?)? = nil, maxConcurrentLookups: Int = 8) {
        self.lookUpName = lookUpName
        self.maxConcurrentLookups = maxConcurrentLookups
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        var unidentified: [DiscoveredDevice] = []
        for device in await accumulator.snapshot() {
            if let update = Self.update(for: device) {
                await accumulator.upsert(update, confirmsPresence: false) // a name says nothing about presence
            } else if lookUpName != nil, Self.needsIdentity(device), Self.identity(for: device) == nil {
                unidentified.append(device)
            }
        }
        if let lookUpName, !unidentified.isEmpty {
            await forEachBounded(unidentified, limit: maxConcurrentLookups, operation: { device -> DiscoveredDevice? in
                guard let name = await lookUpName(device.ipAddress) else { return nil }
                return Self.update(for: device, names: [name])
            }, onResult: { update in
                if let update {
                    await accumulator.upsert(update, confirmsPresence: false)
                }
            })
        }
        await onProgress(1.0)
    }

    /// The device carrying its names' maker and model, or nil when there is nothing to fill.
    static func update(for device: DiscoveredDevice) -> DiscoveredDevice? {
        update(for: device, names: [device.hostname, device.friendlyName])
    }

    static func update(for device: DiscoveredDevice, names: [String?]) -> DiscoveredDevice? {
        guard let identity = HostnameIdentity.identify(names: names) else { return nil }
        let fill = identity.fills(knownMaker: device.maker, knownModel: device.modelName)
        guard fill.maker != nil || fill.model != nil else { return nil }
        return DiscoveredDevice(
            ipAddress: device.ipAddress,
            hostname: nil,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local,
            identity: DeviceIdentity(
                maker: IdentityValue(fill.maker, source: .hostnameGuess),
                model: IdentityValue(fill.model, source: .hostnameGuess)
            )
        )
    }

    private static func identity(for device: DiscoveredDevice) -> HostnameIdentity? {
        HostnameIdentity.identify(names: [device.hostname, device.friendlyName])
    }

    private static func needsIdentity(_ device: DiscoveredDevice) -> Bool {
        device.maker == nil || device.modelName == nil
    }
}
