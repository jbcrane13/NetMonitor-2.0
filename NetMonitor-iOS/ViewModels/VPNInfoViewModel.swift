import Foundation
import NetMonitorCore

/// ViewModel for the VPN Info dashboard card.
@MainActor
@Observable
final class VPNInfoViewModel {

    // MARK: - State

    var vpnStatus: VPNStatus = .inactive
    var connectionDuration: String = ""

    // MARK: - Dependencies

    private let service: any VPNDetectionServiceProtocol
    private var monitorTask: Task<Void, Never>?
    private var durationTimer: Task<Void, Never>?

    init(service: any VPNDetectionServiceProtocol = VPNDetectionService()) {
        self.service = service
    }

    // MARK: - Computed

    var isVPNActive: Bool { vpnStatus.isActive }

    var interfaceName: String { vpnStatus.interfaceName ?? "—" }

    var protocolName: String { vpnStatus.protocolType.rawValue }

    var statusText: String { vpnStatus.isActive ? "Connected" : "Not Connected" }

    // MARK: - Lifecycle

    func startMonitoring() {
        service.startMonitoring()
        vpnStatus = service.status

        monitorTask = Task {
            let stream = service.statusStream()
            for await status in stream {
                guard !Task.isCancelled else { break }
                vpnStatus = status
                updateDurationTimer(for: status)
                // Log VPN changes
                if status.isActive {
                    NetworkEventService.shared.log(
                        type: .vpnConnected,
                        title: "VPN Connected",
                        details: status.interfaceName.map { "Interface: \($0)" },
                        severity: .info
                    )
                } else if !status.isActive && vpnStatus.isActive {
                    NetworkEventService.shared.log(
                        type: .vpnDisconnected,
                        title: "VPN Disconnected",
                        severity: .warning
                    )
                }
            }
        }
    }

    func stopMonitoring() {
        monitorTask?.cancel()
        monitorTask = nil
        durationTimer?.cancel()
        durationTimer = nil
        service.stopMonitoring()
    }

    // MARK: - Private

    private func updateDurationTimer(for status: VPNStatus) {
        durationTimer?.cancel()
        durationTimer = nil

        guard status.isActive, let start = status.connectedSince else {
            connectionDuration = ""
            return
        }

        durationTimer = Task {
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                connectionDuration = Self.formatDuration(elapsed)
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private static func formatDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
