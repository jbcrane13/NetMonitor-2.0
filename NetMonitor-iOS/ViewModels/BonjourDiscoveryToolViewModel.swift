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

        // Poll discoveredServices at regular intervals (10 s deadline, mirrors macOS behaviour)
        pollingTask = Task { @MainActor [weak self] in
            let deadline = Date.now.addingTimeInterval(10)

            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self, !Task.isCancelled else { break }

                // Sync by ID set so remove+add events (same count) are detected.
                let discovered = self.bonjourService.discoveredServices
                let currentIDs = Set(self.services.map(\.id))
                let freshIDs = Set(discovered.map(\.id))
                if currentIDs != freshIDs {
                    self.services = discovered
                }

                if !self.bonjourService.isDiscovering || Date.now >= deadline {
                    self.services = self.bonjourService.discoveredServices
                    break
                }
            }

            guard let self, !Task.isCancelled else { return }
            self.bonjourService.stopDiscovery()
            self.isDiscovering = false
            ToolActivityLog.shared.add(
                tool: "Bonjour",
                target: "Local Network",
                result: "\(self.services.count) services",
                success: !self.services.isEmpty
            )
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
