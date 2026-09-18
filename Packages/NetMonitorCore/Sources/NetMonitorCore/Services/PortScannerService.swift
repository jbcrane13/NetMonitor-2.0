import Foundation
import Network
import NetworkScanKit

public actor PortScannerService: PortScannerServiceProtocol {
    private var isRunning = false
    private var activeRunID: UUID?
    private let maxConcurrent = 20

    public init() {}

    public func scan(
        host: String,
        ports: [Int],
        timeout: TimeInterval = 2
    ) -> AsyncStream<PortScanResult> {
        AsyncStream { continuation in
            Task {
                let runID = self.beginRun()

                await withTaskGroup(of: PortScanResult.self) { group in
                    var pending = 0
                    var portIterator = ports.makeIterator()

                    while self.shouldContinue(runID: runID) {
                        while pending < maxConcurrent, let port = portIterator.next() {
                            pending += 1
                            group.addTask {
                                await self.scanPort(host: host, port: port, timeout: timeout)
                            }
                        }

                        guard let result = await group.next() else { break }
                        pending -= 1

                        continuation.yield(result)
                    }
                }

                self.endRun(runID: runID)
                continuation.finish()
            }
        }
    }

    public func stop() async {
        isRunning = false
        activeRunID = nil
    }

    private func beginRun() -> UUID {
        let runID = UUID()
        activeRunID = runID
        isRunning = true
        return runID
    }

    private func shouldContinue(runID: UUID) -> Bool {
        isRunning && activeRunID == runID
    }

    private func endRun(runID: UUID) {
        guard activeRunID == runID else { return }
        activeRunID = nil
        isRunning = false
    }

    private func scanPort(host: String, port: Int, timeout: TimeInterval) async -> PortScanResult {
        let filteredSentinel = PortScanResult(
            port: port,
            state: .filtered,
            serviceName: PortScanResult.commonServiceName(for: port),
            banner: nil,
            responseTime: nil
        )

        let result = await withConnectionSlot { () async -> PortScanResult in
            let start = Date()

            let endpoint = NWEndpoint.hostPort(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: UInt16(port))!
            )

            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true

            let connection = NWConnection(to: endpoint, using: parameters)

            let portState: PortState = await withNWConnection(
                connection,
                timeout: .seconds(timeout),
                timeoutValue: .filtered
            ) { state in
                switch state {
                case .ready:
                    return .complete(.open)
                case .failed(let error):
                    if case NWError.posix(let code) = error, code == .ECONNREFUSED {
                        return .complete(.closed)
                    }
                    return .complete(.filtered)
                case .cancelled:
                    return .complete(.filtered)
                default:
                    return nil
                }
            }

            let elapsed = Date().timeIntervalSince(start) * 1000

            return PortScanResult(
                port: port,
                state: portState,
                serviceName: PortScanResult.commonServiceName(for: port),
                banner: nil,
                responseTime: portState == .open ? elapsed : nil
            )
        }

        return result ?? filteredSentinel
    }
}
