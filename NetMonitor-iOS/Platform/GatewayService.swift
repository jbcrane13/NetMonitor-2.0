import Foundation
import NetMonitorCore
import Network
import NetworkScanKit

@MainActor
@Observable
final class GatewayService: GatewayServiceProtocol {
    private(set) var gateway: GatewayInfo?
    private(set) var isLoading: Bool = false
    private(set) var lastError: String?

    func detectGateway() async {
        isLoading = true
        lastError = nil

        defer { isLoading = false }

        guard let gatewayIP = NetworkUtilities.detectDefaultGateway() else {
            lastError = "Could not detect gateway"
            gateway = nil
            return
        }

        let latency = await measureLatency(to: gatewayIP)

        gateway = GatewayInfo(
            ipAddress: gatewayIP,
            macAddress: nil,
            vendor: nil,
            latency: latency
        )
    }

    private nonisolated func measureLatency(to host: String) async -> Double? {
        let start = Date()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: 80) ?? .http
        )

        let connection = NWConnection(to: endpoint, using: .tcp)
        defer { connection.cancel() }

        return await withCheckedContinuation { continuation in
            let resumed = NetMonitorCore.ResumeState()

            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(5))
                guard await resumed.tryResume() else { return }
                connection.cancel()
                continuation.resume(returning: nil)
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        let latency = Date().timeIntervalSince(start) * 1000
                        connection.cancel()
                        continuation.resume(returning: latency)
                    }
                case .failed, .cancelled:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        continuation.resume(returning: nil)
                    }
                default:
                    break
                }
            }

            connection.start(queue: .global())
        }
    }
}
