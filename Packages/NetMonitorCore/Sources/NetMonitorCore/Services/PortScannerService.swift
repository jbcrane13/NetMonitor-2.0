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
        await ConnectionBudget.shared.acquire()
        defer { Task { await ConnectionBudget.shared.release() } }

        let start = Date()

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: UInt16(port))!
        )

        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let connection = NWConnection(to: endpoint, using: parameters)
        defer { connection.cancel() }
        
        let portState = await withCheckedContinuation { (continuation: CheckedContinuation<PortState, Never>) in
            let resumed = ResumeState()
            
            let timeoutTask = Task {
                try? await Task.sleep(for: .seconds(timeout))
                guard await resumed.tryResume() else { return }
                connection.cancel()
                continuation.resume(returning: .filtered)
            }
            
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        continuation.resume(returning: .open)
                    }
                case .failed(let error):
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        connection.cancel()
                        if case NWError.posix(let code) = error, code == .ECONNREFUSED {
                            continuation.resume(returning: .closed)
                        } else {
                            continuation.resume(returning: .filtered)
                        }
                    }
                case .cancelled:
                    Task {
                        guard await resumed.tryResume() else { return }
                        timeoutTask.cancel()
                        continuation.resume(returning: .filtered)
                    }
                default:
                    break
                }
            }
            
            connection.start(queue: .global())
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
}
