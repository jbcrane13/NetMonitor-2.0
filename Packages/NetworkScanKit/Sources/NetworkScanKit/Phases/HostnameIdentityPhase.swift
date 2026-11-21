import Foundation

/// Fills an empty maker and model from each device's hostname (#439), for example a switch
/// named `unifi-pro-max-16-switch` becomes Ubiquiti, "UniFi Pro Max 16 Switch".
///
/// Not part of ``ScanPipeline/standard(bonjourServiceProvider:bonjourStopProvider:latencyPhase:trailingSteps:)``:
/// the caller runs it after every other source, including the Mac companion merge on iOS. It
/// only fills empty fields, and the accumulator keeps an existing vendor and model over it.
public struct HostnameIdentityPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .hostnameIdentity
    public let displayName = "Reading device names…"
    public let weight: Double = 0.01

    public init() {}

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        for device in await accumulator.snapshot() {
            guard let update = Self.update(for: device) else { continue }
            await accumulator.upsert(update, confirmsPresence: false) // a name says nothing about presence
        }
        await onProgress(1.0)
    }

    /// The device carrying the hostname's maker and model, or nil when there is nothing to fill.
    static func update(for device: DiscoveredDevice) -> DiscoveredDevice? {
        guard let hostname = device.hostname, let identity = HostnameIdentity.parse(hostname: hostname) else { return nil }
        let knownMaker = [device.vendor, device.manufacturer].compactMap { $0 }.first { !$0.isEmpty }
        let fill = identity.fills(knownMaker: knownMaker, knownModel: device.modelName)
        guard fill.maker != nil || fill.model != nil else { return nil }
        return DiscoveredDevice(
            ipAddress: device.ipAddress,
            hostname: nil,
            vendor: fill.maker,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local,
            modelName: fill.model
        )
    }
}
