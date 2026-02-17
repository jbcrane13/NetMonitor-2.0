import Foundation
import NetMonitorCore

/// ViewModel for the Port Scanner tool view
@MainActor
@Observable
final class PortScannerToolViewModel {
    // MARK: - Input Properties

    var host: String = ""
    var portPreset: PortScanPreset = .common
    var customRange: PortRange = PortRange()

    // MARK: - State Properties

    var isRunning: Bool = false
    var results: [PortScanResult] = []
    var errorMessage: String?
    var scannedCount: Int = 0

    // MARK: - Dependencies

    private let portScannerService: any PortScannerServiceProtocol
    private var scanTask: Task<Void, Never>?

    init(portScannerService: any PortScannerServiceProtocol = PortScannerService(), initialHost: String? = nil) {
        self.portScannerService = portScannerService
        if let initialHost = initialHost {
            self.host = initialHost
        }
    }

    // MARK: - Computed Properties

    var canStartScan: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && !isRunning && totalPorts > 0
    }

    var openPorts: [PortScanResult] {
        results.filter { $0.state == .open }
    }

    /// The effective list of ports to scan based on preset or custom range
    var effectivePorts: [Int] {
        if portPreset.isCustom {
            return customRange.ports
        }
        return portPreset.ports
    }

    var totalPorts: Int {
        effectivePorts.count
    }

    var progress: Double {
        guard totalPorts > 0 else { return 0 }
        return Double(scannedCount) / Double(totalPorts)
    }

    // MARK: - Actions

    func startScan() {
        guard canStartScan else { return }

        clearResults()
        isRunning = true
        scannedCount = 0

        let ports = effectivePorts

        scanTask = Task {
            let timeout = UserDefaults.standard.object(forKey: AppSettings.Keys.portScanTimeout) as? Double ?? 2.0
            let stream = await portScannerService.scan(
                host: host.trimmingCharacters(in: .whitespaces),
                ports: ports,
                timeout: timeout
            )

            for await result in stream {
                scannedCount += 1
                if result.state == .open {
                    results.append(result)
                }
            }

            // Sort by port number
            results.sort { $0.port < $1.port }
            isRunning = false

            ToolActivityLog.shared.add(
                tool: "Port Scan",
                target: host,
                result: "\(openPorts.count) open / \(totalPorts) scanned",
                success: true
            )
        }
    }

    func stopScan() {
        scanTask?.cancel()
        scanTask = nil
        Task {
            await portScannerService.stop()
        }
        isRunning = false
    }

    func clearResults() {
        results.removeAll()
        scannedCount = 0
        errorMessage = nil
    }
}
