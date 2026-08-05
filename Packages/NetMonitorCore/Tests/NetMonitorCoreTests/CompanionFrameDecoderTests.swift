import Foundation
import Testing
@testable import NetMonitorCore

struct CompanionFrameDecoderTests {
    @Test("decoder handles fragmented and adjacent frames")
    func fragmentedAdjacentFrames() async throws {
        let decoder = CompanionFrameDecoder(maximumFrameSize: 1_024)
        let first = try CompanionMessage.heartbeat(HeartbeatPayload(timestamp: Date(), version: "1")).encodeLengthPrefixed()
        let second = try CompanionMessage.error(ErrorPayload(code: "fixture", message: "fixture")).encodeLengthPrefixed()

        let partial = await decoder.append(Data(first.prefix(2)))
        #expect(partial.messages.isEmpty)

        var remainder = Data(first.dropFirst(2))
        remainder.append(second)
        let decoded = await decoder.append(remainder)

        #expect(decoded.messages.count == 2)
        #expect(decoded.errors.isEmpty)
    }

    @Test("oversized frame is rejected and does not poison the next frame")
    func oversizedFrameResetsBuffer() async throws {
        let decoder = CompanionFrameDecoder(maximumFrameSize: 128)

        let rejected = await decoder.append(Data([0, 0, 1, 0]))
        #expect(rejected.errors == [.invalidLength(256)])

        let valid = try CompanionMessage.heartbeat(HeartbeatPayload(timestamp: Date(), version: "1")).encodeLengthPrefixed()
        let decoded = await decoder.append(valid)
        #expect(decoded.messages.count == 1)
    }
}
