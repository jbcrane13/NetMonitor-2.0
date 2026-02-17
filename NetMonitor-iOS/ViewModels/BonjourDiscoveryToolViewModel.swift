import Foundation
import NetMonitorCore

/// ViewModel for the Bonjour Discovery tool view
///
/// Uses the imperative `startDiscovery()` + polling pattern — the same proven
/// approach used by `BonjourScanPhase` in the network scan pipeline. This avoids
/// the fragile `AsyncStream` continuation lifecycle that caused the tool to
/// silently produce zero results.
@MainActor
@Observable
final class BonjourDiscoveryToolViewModel {
    // MARK: - State Properties

    var isDiscovering: Bool = false
    var hasDiscoveredOnce: Bool = false
    var services: [BonjourService] = []
    var errorMessage: String?

    // MARK: - Dependencies

    private let bonjourService: any BonjourDiscoveryServiceProtocol
    private var pollingTask: Task<Void, Never>?

    init(bonjourService: any BonjourDiscoveryServiceProtocol = BonjourDiscoveryService()) {
        self.bonjourService = bonjourService
    }

    // MARK: - Computed Properties

    var groupedServices: [String: [BonjourService]] {
        Dictionary(grouping: services, by: { $0.serviceCategory })
    }

    var sortedCategories: [String] {
        groupedServices.keys.sorted()
    }

    // MARK: - Actions

    func startDiscovery() {
        // Clean up any previous run
        pollingTask?.cancel()
        pollingTask = nil
        bonjourService.stopDiscovery()

        isDiscovering = true
        hasDiscoveredOnce = true
        errorMessage = nil
        services = []

        // Start browsing using the imperative API (same path as network scan)
        bonjourService.startDiscovery(serviceType: nil)

        // Poll discoveredServices at regular intervals
        // (mirrors BonjourScanPhase's adaptive polling approach)
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { break }

                // Sync newly-discovered services from the underlying service
                let discovered = bonjourService.discoveredServices
                if discovered.count != services.count {
                    services = discovered
                }

                // The service auto-stops after its 30s timeout
                if !bonjourService.isDiscovering {
                    services = bonjourService.discoveredServices
                    break
                }
            }

            if !Task.isCancelled {
                isDiscovering = false
                ToolActivityLog.shared.add(
                    tool: "Bonjour",
                    target: "Local Network",
                    result: "\(services.count) services",
                    success: !services.isEmpty
                )
            }
        }
    }

    func stopDiscovery() {
        pollingTask?.cancel()
        pollingTask = nil
        bonjourService.stopDiscovery()
        isDiscovering = false
    }

    func clearResults() {
        services.removeAll()
        errorMessage = nil
    }
}
