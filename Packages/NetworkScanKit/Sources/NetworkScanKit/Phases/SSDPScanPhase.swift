import Foundation
import Network
import os.log

/// Counts and error codes only, never addresses (#381).
private let logger = Logger(subsystem: "com.netmonitor.scankit", category: "SSDP")

/// Discovers devices via SSDP/UPnP M-SEARCH multicast, then reads each device's
/// description (friendly name, maker, model) from its `LOCATION` URL (#387).
public struct SSDPScanPhase: ScanPhase, Sendable {
    public let id: ScanPhaseID = .ssdp
    public let displayName = "UPnP discovery…"
    public let weight: Double = 0.06

    /// SSDP replies: each responder IP with the `LOCATION` values it sent, in order.
    typealias Discover = @Sendable (_ context: ScanContext) async -> [String: [String]]
    /// Fetches a description document; nil on any failure.
    typealias FetchDescription = @Sendable (_ url: URL, _ interface: NWInterface.InterfaceType?) async -> Data?

    /// Description fetches running at once.
    static let maxConcurrentFetches = 4
    /// `LOCATION` URLs tried per device before giving up.
    static let maxLocationsPerDevice = 2

    private let discover: Discover
    private let fetchDescription: FetchDescription

    public init() {
        self.init(
            discover: { context in
                await withConnectionSlot { await SSDPSocketSearch.search(localIP: context.localIP) } ?? [:]
            },
            fetchDescription: { await UPnPDescriptionFetcher.fetch($0, requiredInterfaceType: $1) }
        )
    }

    /// Test seam: replaces multicast discovery and the HTTP fetch.
    init(discover: @escaping Discover, fetchDescription: @escaping FetchDescription) {
        self.discover = discover
        self.fetchDescription = fetchDescription
    }

    public func execute(
        context: ScanContext,
        accumulator: ScanAccumulator,
        onProgress: @Sendable (Double) async -> Void
    ) async {
        guard !Task.isCancelled else { return }
        await onProgress(0.0)

        let replies = await discover(context)
        guard !Task.isCancelled else { return }
        await onProgress(0.5)

        let responders = replies.filter { context.subnetFilter($0.key) }
        for ip in responders.keys.sorted(by: { $0.ipSortKey < $1.ipSortKey }) {
            guard !Task.isCancelled else { return }
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: ip,
                hostname: nil,
                vendor: nil,
                macAddress: nil,
                latency: nil,
                discoveredAt: Date(),
                source: .ssdp
            ))
        }
        await onProgress(0.7)

        let descriptions = await describe(responders, context: context)
        for (ip, description) in descriptions {
            guard !Task.isCancelled else { return }
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: ip,
                hostname: nil,
                vendor: nil,
                macAddress: nil,
                latency: nil,
                discoveredAt: Date(),
                source: .ssdp,
                identity: DeviceIdentity(
                    maker: IdentityValue(description.manufacturer, source: .upnp),
                    model: IdentityValue(description.modelName, source: .upnp),
                    friendlyName: IdentityValue(description.friendlyName, source: .upnp)
                )
            ))
        }

        await onProgress(1.0)
    }

    // MARK: - Device descriptions (#387)

    /// Fetches and parses one description per responder: its first `LOCATION` (up to
    /// ``maxLocationsPerDevice``) that is plain HTTP to an address in the scan subnet and
    /// parses. Each URL is fetched at most once per scan.
    private func describe(
        _ responders: [String: [String]],
        context: ScanContext
    ) async -> [String: UPnPDeviceDescription] {
        let candidates: [(ip: String, urls: [URL])] = responders.compactMap { ip, locations in
            var seen: Set<URL> = []
            let urls = locations.compactMap { location -> URL? in
                guard let url = UPnPDescriptionFetcher.descriptionURL(fromLocation: location, subnetFilter: context.subnetFilter),
                      seen.insert(url).inserted else { return nil }
                return url
            }
            return urls.isEmpty ? nil : (ip, Array(urls.prefix(Self.maxLocationsPerDevice)))
        }
        guard !candidates.isEmpty else { return [:] }

        let fetch = fetchDescription
        let interface = context.requiredInterfaceType
        var results: [String: UPnPDeviceDescription] = [:]
        await forEachBounded(candidates, limit: Self.maxConcurrentFetches, operation: { candidate -> (String, UPnPDeviceDescription?) in
            for url in candidate.urls {
                guard !Task.isCancelled else { break }
                let data = await withConnectionSlot { await fetch(url, interface) } ?? nil
                if let data, let description = UPnPDeviceDescription.parse(data) {
                    return (candidate.ip, description)
                }
            }
            return (candidate.ip, nil)
        }, onResult: { ip, description in
            if let description {
                results[ip] = description
            }
        })
        logger.info("SSDP descriptions: \(results.count) of \(candidates.count) read")
        return results
    }

    /// The `LOCATION` header value of an SSDP reply, if any.
    static func extractLocation(fromSSDPResponse response: String) -> String? {
        for line in response.split(whereSeparator: \.isNewline) where line.lowercased().hasPrefix("location:") {
            let value = line.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
