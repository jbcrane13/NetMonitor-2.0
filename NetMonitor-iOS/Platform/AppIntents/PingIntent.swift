import AppIntents
import NetMonitorCore

/// Siri/Shortcuts intent: ping a host and return average latency.
struct PingIntent: AppIntent {
    static let title: LocalizedStringResource = "Ping a Host"
    static let description = IntentDescription(
        "Ping a network host and return the average latency.",
        categoryName: "Network Tools"
    )

    @Parameter(title: "Host", description: "The hostname or IP address to ping")
    var host: String

    @Parameter(
        title: "Count",
        description: "Number of ping packets to send",
        default: 4,
        inclusiveRange: (1, 20)
    )
    var count: Int

    func perform() async throws -> some IntentResult {
        let trimmed = host.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            throw $host.needsValueError("Enter a hostname or IP address.")
        }

        let service = PingService()
        let stream = await service.ping(host: trimmed, count: count, timeout: 5.0)

        var results: [PingResult] = []
        for await result in stream {
            results.append(result)
        }

        _ = await service.calculateStatistics(results, requestedCount: count)
        return .result()
    }
}
