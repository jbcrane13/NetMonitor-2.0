import AppIntents
import NetMonitorCore

/// Siri/Shortcuts intent: ping a host and return average latency.
struct PingIntent: AppIntent {
    static let title: LocalizedStringResource = "Ping a Host"
    // periphery:ignore
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

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
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

        guard let stats = await service.calculateStatistics(results, requestedCount: count),
              stats.received > 0 else {
            throw PingIntentError.noResponses(host: trimmed)
        }

        let avg = stats.avgTime
        let dialog: IntentDialog = "Average latency to \(trimmed) was \(Int(avg.rounded())) ms across \(stats.received) of \(stats.transmitted) pings."
        return .result(value: avg, dialog: dialog)
    }
}

private enum PingIntentError: Error, LocalizedError {
    case noResponses(host: String)

    var errorDescription: String? {
        switch self {
        case .noResponses(let host):
            return "No ping responses received from \(host)."
        }
    }
}
