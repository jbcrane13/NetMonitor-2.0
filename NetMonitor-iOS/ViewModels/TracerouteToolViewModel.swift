import Foundation
import NetMonitorCore

/// ViewModel for the Traceroute tool view
@MainActor
@Observable
final class TracerouteToolViewModel {
    // MARK: - Input Properties

    var host: String = "" {
        didSet {
            let trimmed = host.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                TargetManager.shared.currentTarget = trimmed
            }
        }
    }

    var maxHops: Int = 30

    // MARK: - State Properties

    var isRunning: Bool = false
    var hops: [TracerouteHop] = []
    var errorMessage: String?

    // MARK: - Configuration

    let availableMaxHops = [15, 30, 64]

    // MARK: - Dependencies

    private let tracerouteService: any TracerouteServiceProtocol
    private var traceTask: Task<Void, Never>?

    init(tracerouteService: any TracerouteServiceProtocol = TracerouteService(), initialHost: String? = nil) {
        self.tracerouteService = tracerouteService
        if let initialHost = initialHost {
            self.host = initialHost
        }
    }

    // MARK: - Computed Properties

    var canStartTrace: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && !isRunning
    }

    var completedHops: Int {
        hops.count
    }

    // MARK: - Actions

    func startTrace() {
        guard canStartTrace else { return }

        let trimmed = host.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            TargetManager.shared.setTarget(trimmed)
        }

        clearResults()
        isRunning = true

        traceTask = Task {
            let stream = await tracerouteService.trace(
                host: host.trimmingCharacters(in: .whitespaces),
                maxHops: maxHops,
                timeout: nil
            )

            for await hop in stream {
                hops.append(hop)
                if hops.count >= maxHops {
                    break
                }
            }

            isRunning = false

            ToolActivityLog.shared.add(
                tool: "Traceroute",
                target: host,
                result: "\(hops.count) hops",
                success: !hops.isEmpty
            )
        }
    }

    func stopTrace() {
        traceTask?.cancel()
        traceTask = nil
        Task {
            await tracerouteService.stop()
        }
        isRunning = false
    }

    func clearResults() {
        hops.removeAll()
        errorMessage = nil
    }
}
