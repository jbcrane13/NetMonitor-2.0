import Foundation
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - CompanionService Framing Tests

/// Tests that `CompanionService` correctly delegates wire framing to Core's
/// `CompanionFrameDecoder` via `processIncomingDataForTesting`.
///
/// These exercise the seam between raw bytes arriving on a connection and the
/// decoded `CompanionMessage`s (or synthesized `DECODE_ERROR` responses) that
/// result — reassembly across partial chunks, multiple frames in one chunk,
/// and the oversize/malformed rejection paths. `CompanionWireProtocolTests`
/// covers the encode/decode layer itself and is unaffected by this seam.
struct CompanionServiceFramingTests {

    @Test("one complete frame decodes to exactly one message")
    func oneFrameDecodesToOneMessage() async throws {
        let service = CompanionService()
        let clientID = UUID()
        let original = CompanionMessage.heartbeat(HeartbeatPayload(version: "2.0"))
        let framed = try original.encodeLengthPrefixed()

        let results = await service.processIncomingDataForTesting(framed, clientID: clientID)

        #expect(results.count == 1)
        guard case .heartbeat(let payload)? = results.first else {
            Issue.record("Expected a decoded heartbeat message, got \(results)")
            return
        }
        #expect(payload.version == "2.0")
    }

    @Test("two frames delivered in a single chunk both decode, in order")
    func twoFramesInOneChunkBothDecode() async throws {
        let service = CompanionService()
        let clientID = UUID()

        let first = CompanionMessage.heartbeat(HeartbeatPayload(version: "1.0"))
        let second = CompanionMessage.command(CommandPayload(action: .refreshDevices))
        var stream = try first.encodeLengthPrefixed()
        try stream.append(second.encodeLengthPrefixed())

        let results = await service.processIncomingDataForTesting(stream, clientID: clientID)

        #expect(results.count == 2)
        guard case .heartbeat? = results.first, case .command(let payload)? = results.last else {
            Issue.record("Expected [heartbeat, command] in order, got \(results)")
            return
        }
        #expect(payload.action == .refreshDevices)
    }

    @Test("one frame split across three chunks decodes only once the final chunk arrives")
    func frameSplitAcrossThreeChunksDecodesOnLastChunk() async throws {
        let service = CompanionService()
        let clientID = UUID()

        let original = CompanionMessage.error(ErrorPayload(code: "E1", message: "fixture"))
        let framed = try original.encodeLengthPrefixed()
        #expect(framed.count >= 6, "Need enough payload bytes to split into three non-trivial chunks")

        let chunk1 = Data(framed.prefix(2))
        let rest = Data(framed.dropFirst(2))
        let chunk2 = Data(rest.prefix(rest.count / 2))
        let chunk3 = Data(rest.dropFirst(chunk2.count))

        let firstResults = await service.processIncomingDataForTesting(chunk1, clientID: clientID)
        #expect(firstResults.isEmpty)

        let secondResults = await service.processIncomingDataForTesting(chunk2, clientID: clientID)
        #expect(secondResults.isEmpty)

        let thirdResults = await service.processIncomingDataForTesting(chunk3, clientID: clientID)
        #expect(thirdResults.count == 1)
        guard case .error(let payload)? = thirdResults.first else {
            Issue.record("Expected the reassembled error message on the final chunk, got \(thirdResults)")
            return
        }
        #expect(payload.code == "E1")
    }

    @Test("frame length exceeding the 1 MiB cap is rejected and does not poison later frames")
    func oversizeLengthRejectedAndBufferRecovers() async throws {
        let service = CompanionService()
        let clientID = UUID()

        let oversizeLength = UInt32(CompanionFrameDecoder.defaultMaximumFrameSize + 1)
        var lengthPrefix = oversizeLength.bigEndian
        let oversizeHeader = Data(bytes: &lengthPrefix, count: 4)

        let rejectedResults = await service.processIncomingDataForTesting(oversizeHeader, clientID: clientID)
        #expect(rejectedResults.isEmpty, "An oversize length must not produce a decoded message or a DECODE_ERROR response")

        // The decoder must have reset its buffer — a subsequent valid frame decodes normally.
        let validFrame = try CompanionMessage.heartbeat(HeartbeatPayload(version: "1.0")).encodeLengthPrefixed()
        let recoveredResults = await service.processIncomingDataForTesting(validFrame, clientID: clientID)
        #expect(recoveredResults.count == 1)
    }

    @Test("malformed JSON payload yields a DECODE_ERROR response")
    func malformedJSONYieldsDecodeErrorResponse() async throws {
        let service = CompanionService()
        let clientID = UUID()

        let garbage = Data([0xFF, 0xFE, 0x00, 0x01, 0xAB, 0xCD])
        var length = UInt32(garbage.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(garbage)

        let results = await service.processIncomingDataForTesting(frame, clientID: clientID)

        #expect(results.count == 1)
        guard case .error(let payload)? = results.first else {
            Issue.record("Expected a DECODE_ERROR response, got \(results)")
            return
        }
        #expect(payload.code == "DECODE_ERROR")
    }
}
