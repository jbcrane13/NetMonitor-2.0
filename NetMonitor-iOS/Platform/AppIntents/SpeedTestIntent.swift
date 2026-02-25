import AppIntents
import NetMonitorCore

/// Siri/Shortcuts intent: run a speed test and return download/upload speeds.
struct SpeedTestIntent: AppIntent {
    static let title: LocalizedStringResource = "Run Speed Test"
    static let description = IntentDescription(
        "Run a network speed test and return download and upload speeds.",
        categoryName: "Network Tools"
    )

    func perform() async throws -> some IntentResult {
        // Create service and call startTest() on the main actor
        let data: SpeedTestData = try await MainActor.run {
            SpeedTestService()
        }.startTest()

        let dl = formatSpeed(data.downloadSpeed)
        let ul = formatSpeed(data.uploadSpeed)
        let latency = String(format: "%.0f ms", data.latency)

        _ = "Download: \(dl), Upload: \(ul), Latency: \(latency)"
        return .result()
    }

}
