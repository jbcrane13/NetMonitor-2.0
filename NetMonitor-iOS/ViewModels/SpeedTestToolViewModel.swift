import Foundation
import NetMonitorCore
import SwiftData

/// ViewModel for the Speed Test tool view
@MainActor
@Observable
final class SpeedTestToolViewModel {
    // MARK: - State Properties

    var isRunning: Bool = false
    var downloadSpeed: Double = 0
    var uploadSpeed: Double = 0
    var latency: Double = 0
    var progress: Double = 0
    var phase: SpeedTestPhase = .idle
    var errorMessage: String?
    var selectedDuration: TimeInterval = UserDefaults.standard.double(forKey: AppSettings.Keys.speedTestDuration) > 0
        ? UserDefaults.standard.double(forKey: AppSettings.Keys.speedTestDuration)
        : 5.0 {
        didSet {
            UserDefaults.standard.set(selectedDuration, forKey: AppSettings.Keys.speedTestDuration)
        }
    }

    // MARK: - Dependencies

    private var service: any SpeedTestServiceProtocol
    private var testTask: Task<Void, Never>?

    init(service: any SpeedTestServiceProtocol = SpeedTestService()) {
        self.service = service
    }

    // MARK: - Computed Properties

    var phaseText: String {
        switch phase {
        case .idle: "Ready"
        case .latency: "Measuring latency..."
        case .download: "Testing download..."
        case .upload: "Testing upload..."
        case .complete: "Complete"
        }
    }

    var downloadSpeedText: String {
        formatSpeed(downloadSpeed)
    }

    var uploadSpeedText: String {
        formatSpeed(uploadSpeed)
    }

    var latencyText: String {
        String(format: "%.0f ms", latency)
    }

    // MARK: - Actions

    func startTest(modelContext: ModelContext) {
        guard !isRunning else { return }

        errorMessage = nil
        isRunning = true
        service.duration = selectedDuration

        testTask = Task {
            do {
                let data = try await service.startTest()

                // Sync state from service
                syncFromService()

                // Create SwiftData model object from plain data
                let result = SpeedTestResult(
                    downloadSpeed: data.downloadSpeed,
                    uploadSpeed: data.uploadSpeed,
                    latency: data.latency,
                    serverName: data.serverName,
                    connectionType: .wifi,
                    success: true
                )

                // Persist result
                modelContext.insert(result)
                try? modelContext.save()

                ToolActivityLog.shared.add(
                    tool: "Speed Test",
                    target: data.serverName ?? "Server",
                    result: "↓\(String(format: "%.0f", data.downloadSpeed)) ↑\(String(format: "%.0f", data.uploadSpeed)) Mbps",
                    success: true
                )
            } catch is CancellationError {
                // User cancelled — no error
                phase = .idle
            } catch {
                errorMessage = NetworkError.from(error).userFacingMessage
                phase = .idle
                ToolActivityLog.shared.add(
                    tool: "Speed Test",
                    target: "Server",
                    result: "Failed",
                    success: false
                )
            }
            isRunning = false
        }

        // Observe service state changes
        Task {
            while isRunning {
                syncFromService()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopTest() {
        service.stopTest()
        testTask?.cancel()
        testTask = nil
        isRunning = false
        phase = .idle
    }

    // MARK: - Helpers

    private func syncFromService() {
        downloadSpeed = service.downloadSpeed
        uploadSpeed = service.uploadSpeed
        latency = service.latency
        progress = service.progress
        phase = service.phase
    }

}
