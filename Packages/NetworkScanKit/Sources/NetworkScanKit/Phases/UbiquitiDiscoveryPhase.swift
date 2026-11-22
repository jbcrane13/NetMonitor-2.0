import Foundation

/// Asks every host in the subnet the Ubiquiti discovery question (UDP 10001) and records the
/// maker, model code and name of each UniFi device that answers (#439).
public struct UbiquitiDiscoveryPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .ubiquitiDiscovery
    public let displayName = "UniFi discovery…"
    public let weight: Double = 0.03

    typealias Discover = @Sendable (_ context: ScanContext) async -> [String: UbiquitiDeviceInfo]
    private let discover: Discover

    public init() {
        self.init(discover: { context in
            await withConnectionSlot {
                await UbiquitiDiscovery.discover(hosts: context.hosts, localIP: context.localIP)
            } ?? [:]
        })
    }

    /// Test seam: replaces the UDP exchange.
    init(discover: @escaping Discover) {
        self.discover = discover
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)
        let devices = await discover(context).filter { context.subnetFilter($0.key) }
        for ip in devices.keys.sorted(by: { $0.ipSortKey < $1.ipSortKey }) {
            guard !Task.isCancelled, let info = devices[ip] else { return }
            // Only a model code proves UniFi hardware; UniFi controller software on another
            // computer can answer with a name alone. An answer proves the device is there.
            let maker = info.model == nil ? nil : "Ubiquiti"
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: ip,
                hostname: nil,
                vendor: nil,
                macAddress: nil,
                latency: nil,
                discoveredAt: Date(),
                source: .local,
                identity: DeviceIdentity(
                    maker: IdentityValue(maker, source: .unifi),
                    model: IdentityValue(info.model, source: .unifi),
                    friendlyName: IdentityValue(info.name, source: .unifi)
                )
            ))
        }
        await onProgress(1.0)
    }
}
