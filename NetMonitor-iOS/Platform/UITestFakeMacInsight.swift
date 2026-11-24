import Foundation
import NetMonitorCore
import Synchronization

/// A scripted Mac for the insight UI tests (#457), chosen with `UITEST_MAC_INSIGHT`: this
/// phone's model is unavailable, and a connected Mac advertises `insight.v1`. With "answer"
/// it replies to each request with `answer`; with "disconnect" the link drops mid-request.
/// Only the transport is fake: routing, the client's request handling and the marker are real.
enum UITestFakeMacInsight {
    enum Mode: String {
        case answer
        case disconnect
    }

    /// States no number, so it stays grounded whatever the scan finds.
    static let answer = "None of the mail services on this device answered, so nothing here is accepting mail."

    /// The scripted Mac's client; nil outside insight UI tests.
    static let client: CompanionInsightClient? = {
        guard ProcessInfo.processInfo.arguments.contains("--uitesting"),
              let mode = ProcessInfo.processInfo.environment["UITEST_MAC_INSIGHT"].flatMap(Mode.init(rawValue:))
        else { return nil }
        let box = Mutex<CompanionInsightClient?>(nil)
        let client = CompanionInsightClient(send: { message in
            guard case let .insightRequest(request) = message,
                  let client = box.withLock({ $0 }) else { return false }
            // On the main actor, as `MacConnectionService` reports to the real client.
            Task { @MainActor in
                // Long enough for the test to see the request in flight.
                try? await Task.sleep(for: .seconds(1))
                switch mode {
                case .answer: client.received(InsightResponsePayload(requestID: request.requestID, answer: answer))
                case .disconnect: client.disconnected()
                }
            }
            return true
        })
        box.withLock { $0 = client }
        client.received(heartbeat: HeartbeatPayload(capabilities: [CompanionCapability.insight]))
        return client
    }()
}
