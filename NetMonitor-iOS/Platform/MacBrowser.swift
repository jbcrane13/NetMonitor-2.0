import Foundation
import NetMonitorCore
import Network
import os

/// Finds Macs advertising the companion service over Bonjour, with what their TXT record says
/// (#590). `MacConnectionService` owns one and reads endpoints from it.
@MainActor @Observable final class MacBrowser {
    private(set) var discoveredMacs: [DiscoveredMac] = []
    private(set) var isBrowsing = false
    /// Told when the Bonjour browser fails.
    var onFailure: ((String) -> Void)?

    /// Maps DiscoveredMac.id → NWEndpoint for connection lookups
    private var endpoints: [String: NWEndpoint] = [:]
    private var browser: NWBrowser?
    private let queue = DispatchQueue(label: "com.netmonitor.macbrowser", qos: .userInitiated)
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.blakemiller.netmonitor", category: "MacBrowser")

    func start() {
        stop()
        isBrowsing = true
        discoveredMacs = []
        #if DEBUG
        if let fake = UITestFakeMacPairing.discovered {
            discoveredMacs = [fake.mac]
            endpoints = [fake.mac.id: fake.endpoint]
            return
        }
        #endif

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(type: CompanionLink.serviceType, domain: nil)
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let newBrowser = NWBrowser(for: descriptor, using: parameters)

        newBrowser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                switch state {
                case .ready:
                    Self.logger.info("NWBrowser ready — scanning for \(CompanionLink.serviceType, privacy: .public)")
                case .failed(let error):
                    Self.logger.error("NWBrowser failed: \(error, privacy: .public)")
                    self.isBrowsing = false
                    self.onFailure?("Bonjour browser failed: \(error.localizedDescription)")
                case .cancelled:
                    Self.logger.info("NWBrowser cancelled")
                    self.isBrowsing = false
                case .waiting(let error):
                    Self.logger.warning("NWBrowser waiting: \(error, privacy: .public)")
                default:
                    break
                }
            }
        }
        newBrowser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.handle(results)
            }
        }
        newBrowser.start(queue: queue)
        browser = newBrowser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        isBrowsing = false
    }

    func endpoint(for mac: DiscoveredMac) -> NWEndpoint? {
        endpoints[mac.id]
    }

    /// The endpoint of the listed Mac with this ID, if any.
    func endpoint(forMacID macID: UUID) -> NWEndpoint? {
        discoveredMacs.first { $0.macID == macID }.flatMap { endpoints[$0.id] }
    }

    /// A Mac at `endpoint`, as if Bonjour had found it.
    func add(_ mac: DiscoveredMac, endpoint: NWEndpoint) {
        discoveredMacs.append(mac)
        endpoints[mac.id] = endpoint
    }

    private func handle(_ results: Set<NWBrowser.Result>) {
        var macs: [DiscoveredMac] = []
        var found: [String: NWEndpoint] = [:]
        for result in results {
            if case let .service(name, _, _, _) = result.endpoint {
                let id = "\(name)-\(result.endpoint.debugDescription)"
                var macID: UUID?
                var version: Int?
                if case .bonjour(let txt) = result.metadata {
                    (macID, version) = CompanionServiceTXT.read(txt)
                }
                macs.append(DiscoveredMac(id: id, name: name, macID: macID, protocolVersion: version))
                found[id] = result.endpoint
            }
        }
        endpoints = found
        discoveredMacs = macs
    }
}
