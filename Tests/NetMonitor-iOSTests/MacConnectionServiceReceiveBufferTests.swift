import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

@Suite("MacConnectionService receive buffer")
@MainActor
struct MacConnectionServiceReceiveBufferTests {

    @Test("processReceiveBuffer handles back-to-back frames after buffer advances")
    func processReceiveBufferHandlesBackToBackFrames() throws {
        let service = MacConnectionService.shared
        service.disconnect()

        let first = CompanionMessage.statusUpdate(StatusUpdatePayload(
            isMonitoring: true,
            onlineTargets: 1,
            offlineTargets: 0,
            averageLatency: 12.3
        ))
        let second = CompanionMessage.statusUpdate(StatusUpdatePayload(
            isMonitoring: false,
            onlineTargets: 2,
            offlineTargets: 1,
            averageLatency: nil
        ))

        let firstFrame = try first.encodeLengthPrefixed()
        let secondFrame = try second.encodeLengthPrefixed()
        var combined = firstFrame
        combined.append(secondFrame)

        service.processIncomingDataForTesting(combined)

        #expect(service.lastStatusUpdate?.onlineTargets == 2)
        #expect(service.lastStatusUpdate?.offlineTargets == 1)
        #expect(service.lastStatusUpdate?.isMonitoring == false)
    }
}
