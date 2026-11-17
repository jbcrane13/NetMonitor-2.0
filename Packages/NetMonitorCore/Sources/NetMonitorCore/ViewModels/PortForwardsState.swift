import Foundation
import NetworkScanKit

/// One port forward as the Port Forwards tool shows it (#400).
public struct PortForwardRow: Identifiable, Sendable, Equatable {
    public var id: String { "\(protocolName)-\(externalPort)" }
    public let externalPort: Int
    public let protocolName: String
    public let internalClient: String
    /// The known device at `internalClient`, when there is one.
    public let deviceName: String?
    public let internalPort: Int
    public let description: String
    public let leaseText: String
    public let isEnabled: Bool

    /// The device name, else the internal client address.
    public var clientLabel: String { deviceName ?? internalClient }
}

/// Shared state for the Port Forwards tool on macOS and iOS (#400).
@MainActor
@Observable
public final class PortForwardsState {
    public enum Phase: Equatable, Sendable {
        case idle
        case loading
        /// No IPv4 network on the interface.
        case noLocalNetwork
        /// Nothing answered the SSDP search. On iPhone this is the likely result until
        /// the multicast entitlement is granted (#381).
        case noGateway
        /// Devices answered but none is a router with a WAN connection service.
        case noWANService
        /// `isComplete` false: reading stopped early, so forwards may be missing.
        case loaded([PortForwardRow], isComplete: Bool)
    }

    public private(set) var phase: Phase = .idle

    private let service: any UPnPPortMappingServiceProtocol
    private var task: Task<Void, Never>?

    public init(service: any UPnPPortMappingServiceProtocol = UPnPPortMappingService()) {
        self.service = service
    }

    public var isLoading: Bool { phase == .loading }

    /// Reads the forwards on `interface`; `deviceNames` maps IPs to known device names.
    public func load(interface: String, deviceNames: [String: String]) {
        task?.cancel()
        phase = .loading
        let service = service
        task = Task { [weak self] in
            let report = await service.readPortMappings(interface: interface)
            guard !Task.isCancelled else { return }
            self?.phase = Self.phase(for: report, deviceNames: deviceNames)
        }
    }

    /// Waits for the current load; for tests.
    public func waitForLoad() async {
        await task?.value
    }

    public func cancel() {
        task?.cancel()
        task = nil
        if phase == .loading {
            phase = .idle
        }
    }

    static func phase(for report: UPnPPortMappingReport?, deviceNames: [String: String]) -> Phase {
        guard let report else { return .noLocalNetwork }
        switch report {
        case .noGateway: return .noGateway
        case .noWANService: return .noWANService
        case let .mappings(mappings, isComplete):
            return .loaded(rows(from: mappings, deviceNames: deviceNames), isComplete: isComplete)
        }
    }

    /// Rows sorted by external port, then protocol.
    public static func rows(from mappings: [UPnPPortMapping], deviceNames: [String: String]) -> [PortForwardRow] {
        mappings
            .map { mapping in
                PortForwardRow(
                    externalPort: Int(mapping.externalPort),
                    protocolName: mapping.transportProtocol.rawValue,
                    internalClient: mapping.internalClient,
                    deviceName: deviceNames[mapping.internalClient].flatMap { $0.isEmpty ? nil : $0 },
                    internalPort: Int(mapping.internalPort),
                    description: mapping.description,
                    leaseText: leaseText(seconds: mapping.leaseSeconds),
                    isEnabled: mapping.isEnabled
                )
            }
            .sorted { ($0.externalPort, $0.protocolName) < ($1.externalPort, $1.protocolName) }
    }

    /// "Permanent" for 0, otherwise the time left such as "45 s", "12 min", "1 h 21 min".
    public static func leaseText(seconds: Int) -> String {
        guard seconds > 0 else { return "Permanent" }
        if seconds < 60 {
            return "\(seconds) s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes) min"
        }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours) h" : "\(hours) h \(rest) min"
    }
}
