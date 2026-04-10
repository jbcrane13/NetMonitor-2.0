import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

@MainActor
struct GatewayServiceTests {

    /// Build a real GatewayService with a MockPingService and a fixed gateway IP.
    /// gatewayIP nil simulates "no gateway found".
    func makeService(
        pingResults: [PingResult] = [],
        gatewayIP: String? = "192.168.1.1"
    ) -> GatewayService {
        let ping = MockPingService()
        ping.mockResults = pingResults
        return GatewayService(pingService: ping, gatewayIPProvider: { gatewayIP })
    }

    @Test func latencyHistoryAccumulatesOnDetectGateway() async {
        let svc = makeService(pingResults: [
            PingResult(sequence: 1, host: "192.168.1.1", ttl: 64, time: 10.0, isTimeout: false)
        ])
        #expect(svc.latencyHistory.isEmpty)

        await svc.detectGateway()

        #expect(svc.latencyHistory.count == 1)
        #expect(svc.latencyHistory[0] == 10.0)
    }

    @Test func latencyHistoryCapAt60() async {
        let svc = makeService(pingResults: [
            PingResult(sequence: 1, host: "192.168.1.1", ttl: 64, time: 5.0, isTimeout: false)
        ])

        for _ in 0..<70 {
            await svc.detectGateway()
        }

        #expect(svc.latencyHistory.count <= 60)
        #expect(svc.latencyHistory.count == 60)
    }

    @Test func measureLatencyReturnsBestOfThree() async {
        let svc = makeService(pingResults: [
            PingResult(sequence: 1, host: "192.168.1.1", ttl: 64, time: 50.0, isTimeout: false),
            PingResult(sequence: 2, host: "192.168.1.1", ttl: 64, time: 20.0, isTimeout: false),
            PingResult(sequence: 3, host: "192.168.1.1", ttl: 64, time: 80.0, isTimeout: false)
        ])

        await svc.detectGateway()

        // latencyHistory stores newest-first; the best-of-three is 20ms
        #expect(svc.latencyHistory.first == 20.0)
    }

    @Test func detectGatewayWithNoGatewayDoesNotAddToHistory() async {
        let ping = MockPingService()
        let svc = GatewayService(pingService: ping, gatewayIPProvider: { nil })

        await svc.detectGateway()

        #expect(svc.latencyHistory.isEmpty)
    }
}
