import AppIntents
import NetMonitorCore

/// Siri/Shortcuts intent: run a speed test and return download/upload speeds.
struct SpeedTestIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Speed Test"
    // periphery:ignore
    static let description = IntentDescription(
        "Run a network speed test and return download and upload speeds.",
        categoryName: "Network Tools"
    )

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let service = await MainActor.run { SpeedTestService() }
        let data = try await service.startTest()

        let dl = formatSpeed(data.downloadSpeed)
        let ul = formatSpeed(data.uploadSpeed)
        let latency = String(format: "%.0f ms", data.latency)
        let dialog: IntentDialog = "Speed test — \(dl) down, \(ul) up, \(latency) latency."

        return .result(value: data.downloadSpeed, dialog: dialog)
    }
}
