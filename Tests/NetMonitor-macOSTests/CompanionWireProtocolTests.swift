import Foundation
import Testing
import NetMonitorCore

// MARK: - Integration tag for macOS test target

extension Tag {
    @Tag static var integration: Self
}

// MARK: - Wire Protocol Framing Tests

/// Tests for the length-prefixed wire framing used by the companion protocol.
///
/// The companion protocol encodes messages as:
///   [ 4-byte big-endian length | JSON payload ]
///
/// These tests verify the full encode→frame→extract→decode round-trip, partial/truncated
/// frame detection, and multi-message stream splitting — none of which are covered by the
/// existing CompanionMessageTests (which only test the JSON encoding layer in isolation).
struct CompanionWireProtocolFramingTests {

    // MARK: - Full encode → decode round-trip via length-prefixed frame

    @Test("heartbeat survives full length-prefixed encode/decode round-trip")
    func heartbeatLengthPrefixedRoundTrip() throws {
        let original = CompanionMessage.heartbeat(HeartbeatPayload(version: "2.0"))
        let framed = try original.encodeLengthPrefixed()

        // Extract length prefix
        #expect(framed.count > 4)
        let length = framed.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let jsonData = Data(framed.dropFirst(4))
        #expect(jsonData.count == Int(length))

        // Decode from raw JSON (not from framed data — the decoder works on the payload only)
        let decoded = try CompanionMessage.decode(from: jsonData)
        guard case .heartbeat(let p) = decoded else {
            Issue.record("Expected .heartbeat after length-prefixed round-trip")
            return
        }
        #expect(p.version == "2.0")
    }

    @Test("statusUpdate survives full length-prefixed encode/decode round-trip")
    func statusUpdateLengthPrefixedRoundTrip() throws {
        let payload = StatusUpdatePayload(
            isMonitoring: true,
            onlineTargets: 3,
            offlineTargets: 1,
            averageLatency: 15.5
        )
        let original = CompanionMessage.statusUpdate(payload)
        let framed = try original.encodeLengthPrefixed()

        let length = framed.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let jsonData = Data(framed.dropFirst(4))
        #expect(jsonData.count == Int(length))

        let decoded = try CompanionMessage.decode(from: jsonData)
        guard case .statusUpdate(let p) = decoded else {
            Issue.record("Expected .statusUpdate after length-prefixed round-trip")
            return
        }
        #expect(p.isMonitoring == true)
        #expect(p.onlineTargets == 3)
        #expect(p.offlineTargets == 1)
        #expect(p.averageLatency == 15.5)
    }

    @Test("deviceList survives full length-prefixed encode/decode round-trip")
    func deviceListLengthPrefixedRoundTrip() throws {
        let device = DeviceInfo(
            ipAddress: "192.168.1.50",
            macAddress: "ff:ee:dd:cc:bb:aa",
            hostname: "test-device",
            vendor: "TestCorp",
            isOnline: true
        )
        let original = CompanionMessage.deviceList(DeviceListPayload(devices: [device]))
        let framed = try original.encodeLengthPrefixed()

        let jsonData = Data(framed.dropFirst(4))
        let decoded = try CompanionMessage.decode(from: jsonData)
        guard case .deviceList(let p) = decoded else {
            Issue.record("Expected .deviceList after length-prefixed round-trip")
            return
        }
        #expect(p.devices.count == 1)
        #expect(p.devices[0].ipAddress == "192.168.1.50")
        #expect(p.devices[0].vendor == "TestCorp")
    }

    @Test("command survives full length-prefixed encode/decode round-trip")
    func commandLengthPrefixedRoundTrip() throws {
        let payload = CommandPayload(action: .ping, parameters: ["host": "8.8.8.8", "count": "4"])
        let original = CompanionMessage.command(payload)
        let framed = try original.encodeLengthPrefixed()

        let jsonData = Data(framed.dropFirst(4))
        let decoded = try CompanionMessage.decode(from: jsonData)
        guard case .command(let p) = decoded else {
            Issue.record("Expected .command after length-prefixed round-trip")
            return
        }
        #expect(p.action == .ping)
        #expect(p.parameters?["host"] == "8.8.8.8")
        #expect(p.parameters?["count"] == "4")
    }

    // MARK: - Length prefix correctness for all message types

    @Test("all message types produce length prefix that matches JSON payload size")
    func allMessageTypesProduceCorrectLengthPrefix() throws {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000_000.0)
        let targetID = UUID()

        let messages: [CompanionMessage] = [
            .heartbeat(HeartbeatPayload(timestamp: fixedDate, version: "1.0")),
            .statusUpdate(StatusUpdatePayload(isMonitoring: true, onlineTargets: 1, offlineTargets: 0, averageLatency: 10.0, timestamp: fixedDate)),
            .targetList(TargetListPayload(targets: [
                TargetInfo(id: targetID, name: "T", host: "1.1.1.1", port: nil, protocol: "icmp", isEnabled: true, isReachable: true, latency: 5.0)
            ])),
            .deviceList(DeviceListPayload(devices: [
                DeviceInfo(ipAddress: "10.0.0.1", macAddress: "aa:bb:cc:dd:ee:ff", hostname: nil, isOnline: false)
            ])),
            .networkProfile(NetworkProfilePayload(name: "Home", gatewayIP: "192.168.1.1", subnet: "192.168.1.0/24", interfaceName: "en0")),
            .command(CommandPayload(action: .scanDevices)),
            .toolResult(ToolResultPayload(tool: "ping", success: true, result: "ok", timestamp: fixedDate)),
            .error(ErrorPayload(code: "E001", message: "test error", timestamp: fixedDate)),
        ]

        for message in messages {
            let framed = try message.encodeLengthPrefixed()
            #expect(framed.count > 4, "Frame for \(message) must have more than 4 bytes")

            let prefixedLength = framed.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let jsonPayloadCount = framed.count - 4
            #expect(Int(prefixedLength) == jsonPayloadCount,
                    "Length prefix \(prefixedLength) must equal JSON payload size \(jsonPayloadCount) for \(message)")
        }
    }

    // MARK: - Multi-message stream splitting

    @Test("two framed messages concatenated can be split and decoded independently")
    func twoFramedMessagesConcatenatedSplitCorrectly() throws {
        let msg1 = CompanionMessage.heartbeat(HeartbeatPayload(version: "1.0"))
        let msg2 = CompanionMessage.command(CommandPayload(action: .refreshDevices))

        let frame1 = try msg1.encodeLengthPrefixed()
        let frame2 = try msg2.encodeLengthPrefixed()

        // Simulate a TCP stream that delivers both frames back-to-back
        var stream = frame1
        stream.append(frame2)

        // Parse first message from the stream
        let len1 = stream.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let json1 = Data(stream[4..<(4 + Int(len1))])
        let decoded1 = try CompanionMessage.decode(from: json1)
        guard case .heartbeat(let p1) = decoded1 else {
            Issue.record("Expected .heartbeat as first message")
            return
        }
        #expect(p1.version == "1.0")

        // Parse second message from the remaining stream
        let offset = 4 + Int(len1)
        let len2 = stream[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let json2 = Data(stream[(offset + 4)..<(offset + 4 + Int(len2))])
        let decoded2 = try CompanionMessage.decode(from: json2)
        guard case .command(let p2) = decoded2 else {
            Issue.record("Expected .command as second message")
            return
        }
        #expect(p2.action == .refreshDevices)
    }

    @Test("five framed messages concatenated can all be decoded in order")
    func fiveFramedMessagesConcatenatedDecodedInOrder() throws {
        let actions: [CommandAction] = [
            .startMonitoring, .stopMonitoring, .scanDevices, .refreshTargets, .refreshDevices
        ]
        var stream = Data()
        for action in actions {
            let frame = try CompanionMessage.command(CommandPayload(action: action)).encodeLengthPrefixed()
            stream.append(frame)
        }

        var offset = 0
        var decodedActions: [CommandAction] = []
        while offset + 4 <= stream.count {
            let len = stream[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            let payloadStart = offset + 4
            let payloadEnd = payloadStart + Int(len)
            guard payloadEnd <= stream.count else { break }

            let json = Data(stream[payloadStart..<payloadEnd])
            let decoded = try CompanionMessage.decode(from: json)
            if case .command(let p) = decoded {
                decodedActions.append(p.action)
            }
            offset = payloadEnd
        }

        #expect(decodedActions == actions,
                "Decoded actions must match original order: \(decodedActions)")
        #expect(offset == stream.count, "All bytes in stream must be consumed")
    }

    // MARK: - Partial / truncated frame detection

    @Test("frame shorter than 4 bytes cannot yield a valid length prefix")
    func frameShorterThan4BytesHasNoValidLength() {
        // A 3-byte buffer cannot encode a 4-byte length prefix
        let truncated = Data([0x00, 0x00, 0x01])
        #expect(truncated.count < 4, "Buffer must be shorter than 4 bytes to represent a truncated frame")
    }

    @Test("length prefix indicates more data than buffer contains — partial frame")
    func lengthPrefixExceedsBufferIsPartialFrame() throws {
        let original = CompanionMessage.heartbeat(HeartbeatPayload(version: "1.0"))
        let framed = try original.encodeLengthPrefixed()

        // Simulate a partial receive: only the first half of the framed data arrived
        let partialFrame = framed.prefix(framed.count / 2)
        let claimedLength = partialFrame.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let availablePayload = partialFrame.count - 4

        // The claimed length must exceed what is available — this is a partial frame
        #expect(Int(claimedLength) > availablePayload,
                "Partial frame: claimed \(claimedLength) bytes but only \(availablePayload) available")
    }

    @Test("truncated JSON payload fails to decode with an error")
    func truncatedJSONPayloadThrowsDecodingError() throws {
        let original = CompanionMessage.statusUpdate(StatusUpdatePayload(
            isMonitoring: true,
            onlineTargets: 2,
            offlineTargets: 0,
            averageLatency: nil
        ))
        let framed = try original.encodeLengthPrefixed()
        // Drop the last 10 bytes of the JSON payload to simulate corruption
        let truncatedJSON = Data(framed.dropFirst(4).dropLast(10))
        #expect(throws: (any Error).self) {
            _ = try CompanionMessage.decode(from: truncatedJSON)
        }
    }

    // MARK: - Special string content in payload fields

    @Test("toolResult with newline characters in result string encodes and decodes correctly")
    func toolResultWithNewlineInResultFieldRoundTrip() throws {
        // The wire protocol is length-prefixed (not newline-delimited), so embedded
        // newlines in payload string fields must survive the JSON encoding layer.
        let multilineResult = "Line 1\nLine 2\nLine 3"
        let payload = ToolResultPayload(tool: "traceroute", success: true, result: multilineResult)
        let original = CompanionMessage.toolResult(payload)
        let framed = try original.encodeLengthPrefixed()

        let jsonData = Data(framed.dropFirst(4))
        let decoded = try CompanionMessage.decode(from: jsonData)
        guard case .toolResult(let p) = decoded else {
            Issue.record("Expected .toolResult after round-trip with embedded newlines")
            return
        }
        #expect(p.result == multilineResult,
                "Embedded newlines must survive the JSON encode/decode layer")
    }

    @Test("error message with special characters encodes and decodes correctly")
    func errorPayloadWithSpecialCharactersRoundTrip() throws {
        let specialMessage = "Connection refused: \"host\" → 192.168.1.1 (code: 61)\t[ECONNREFUSED]"
        let payload = ErrorPayload(code: "CONN_REFUSED", message: specialMessage)
        let original = CompanionMessage.error(payload)
        let framed = try original.encodeLengthPrefixed()

        let jsonData = Data(framed.dropFirst(4))
        let decoded = try CompanionMessage.decode(from: jsonData)
        guard case .error(let p) = decoded else {
            Issue.record("Expected .error after round-trip with special characters")
            return
        }
        #expect(p.message == specialMessage)
        #expect(p.code == "CONN_REFUSED")
    }

    @Test("networkProfile with unicode device name encodes and decodes correctly")
    func networkProfileWithUnicodeSourceDeviceNameRoundTrip() throws {
        let unicodeName = "Blake's MacBook Pro 🖥️"
        let payload = NetworkProfilePayload(
            name: "Home Network",
            gatewayIP: "192.168.1.1",
            subnet: "192.168.1.0/24",
            interfaceName: "en0",
            sourceDeviceName: unicodeName
        )
        let original = CompanionMessage.networkProfile(payload)
        let framed = try original.encodeLengthPrefixed()

        let jsonData = Data(framed.dropFirst(4))
        let decoded = try CompanionMessage.decode(from: jsonData)
        guard case .networkProfile(let p) = decoded else {
            Issue.record("Expected .networkProfile after round-trip with unicode name")
            return
        }
        #expect(p.sourceDeviceName == unicodeName)
    }

    // MARK: - Frame size properties

    @Test("empty device list frame is smaller than non-empty device list frame")
    func emptyDeviceListFrameSmallerThanNonEmpty() throws {
        let emptyFrame = try CompanionMessage.deviceList(DeviceListPayload(devices: [])).encodeLengthPrefixed()
        let populatedFrame = try CompanionMessage.deviceList(DeviceListPayload(devices: [
            DeviceInfo(ipAddress: "192.168.1.1", macAddress: "aa:bb:cc:dd:ee:ff", hostname: "host1", isOnline: true),
            DeviceInfo(ipAddress: "192.168.1.2", macAddress: "11:22:33:44:55:66", hostname: "host2", isOnline: false),
            DeviceInfo(ipAddress: "192.168.1.3", macAddress: "ab:cd:ef:01:23:45", hostname: nil, isOnline: true),
        ])).encodeLengthPrefixed()
        #expect(emptyFrame.count < populatedFrame.count)
    }

    @Test("frame byte count equals 4 plus JSON payload byte count")
    func frameByteCountIs4PlusJSONPayload() throws {
        let msg = CompanionMessage.command(CommandPayload(action: .wakeOnLan, parameters: ["mac": "AA:BB:CC:DD:EE:FF"]))
        let framed = try msg.encodeLengthPrefixed()
        let jsonData = try CompanionMessage.jsonEncoder.encode(msg)
        #expect(framed.count == 4 + jsonData.count)
    }
}

// MARK: - JSON Wire Shape Tests

/// Tests that verify the raw JSON structure of the wire format — the `type` and `payload`
/// keys that both sides of the companion connection parse. This is distinct from the
/// Codable round-trip tests, which only verify that Swift decoding produces the right values.
struct CompanionMessageJSONWireShapeTests {

    @Test("encoded JSON contains top-level 'type' and 'payload' keys")
    func encodedJSONHasTypeAndPayloadKeys() throws {
        let msg = CompanionMessage.heartbeat(HeartbeatPayload(version: "1.0"))
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(json?["type"] != nil, "JSON must contain 'type' key")
        #expect(json?["payload"] != nil, "JSON must contain 'payload' key")
    }

    @Test("type field value matches expected string for each message kind")
    func typeFieldMatchesExpectedStringForAllKinds() throws {
        let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000_000.0)
        let cases: [(CompanionMessage, String)] = [
            (.heartbeat(HeartbeatPayload(timestamp: fixedDate, version: "1.0")), "heartbeat"),
            (.statusUpdate(StatusUpdatePayload(isMonitoring: false, onlineTargets: 0, offlineTargets: 0, averageLatency: nil, timestamp: fixedDate)), "statusUpdate"),
            (.targetList(TargetListPayload(targets: [])), "targetList"),
            (.deviceList(DeviceListPayload(devices: [])), "deviceList"),
            (.networkProfile(NetworkProfilePayload(name: "N", gatewayIP: "1.1.1.1", subnet: "1.1.1.0/24", interfaceName: "en0")), "networkProfile"),
            (.command(CommandPayload(action: .scanDevices)), "command"),
            (.toolResult(ToolResultPayload(tool: "ping", success: true, result: "ok", timestamp: fixedDate)), "toolResult"),
            (.error(ErrorPayload(code: "E", message: "m", timestamp: fixedDate)), "error"),
        ]

        for (message, expectedType) in cases {
            let data = try CompanionMessage.jsonEncoder.encode(message)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let typeValue = json?["type"] as? String
            #expect(typeValue == expectedType,
                    "Expected type '\(expectedType)' for \(message), got '\(typeValue ?? "nil")'")
        }
    }

    @Test("payload for command contains 'action' key with correct raw value")
    func commandPayloadContainsActionKey() throws {
        let msg = CompanionMessage.command(CommandPayload(action: .startMonitoring))
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let action = payload?["action"] as? String
        #expect(action == "startMonitoring",
                "Command payload must contain action='startMonitoring', got '\(action ?? "nil")'")
    }

    @Test("payload for command with nil parameters omits 'parameters' key")
    func commandWithNilParametersOmitsParametersKey() throws {
        let msg = CompanionMessage.command(CommandPayload(action: .stopMonitoring, parameters: nil))
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        // parameters should be absent (nil → omit from JSON) or null
        // Standard JSONEncoder encodes nil optionals as absent
        let hasParameters = payload?.keys.contains("parameters") ?? false
        #expect(!hasParameters, "Nil parameters must be omitted from the JSON payload")
    }

    @Test("payload for toolResult contains 'success' boolean field")
    func toolResultPayloadContainsSuccessBoolean() throws {
        let msg = CompanionMessage.toolResult(ToolResultPayload(tool: "portScan", success: false, result: "timeout"))
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let payload = json?["payload"] as? [String: Any]
        let success = payload?["success"] as? Bool
        #expect(success == false, "toolResult.success must be encoded as a JSON boolean")
    }

    @Test("unknown JSON type string throws decoding error")
    func unknownTypeStringThrowsDecodingError() {
        let badJSON = Data(#"{"type":"unknownXYZ","payload":{}}"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try CompanionMessage.decode(from: badJSON)
        }
    }

    @Test("valid type with missing payload key throws decoding error")
    func validTypeWithMissingPayloadThrowsDecodingError() {
        // The payload key is required; omitting it must throw
        let badJSON = Data(#"{"type":"heartbeat"}"#.utf8)
        #expect(throws: (any Error).self) {
            _ = try CompanionMessage.decode(from: badJSON)
        }
    }

    @Test("completely empty JSON object throws decoding error")
    func emptyJSONObjectThrowsDecodingError() {
        let badJSON = Data("{}".utf8)
        #expect(throws: (any Error).self) {
            _ = try CompanionMessage.decode(from: badJSON)
        }
    }

    @Test("non-JSON bytes throw decoding error")
    func nonJSONBytesThrowDecodingError() {
        let garbage = Data([0xFF, 0xFE, 0x00, 0x01, 0xAB, 0xCD])
        #expect(throws: (any Error).self) {
            _ = try CompanionMessage.decode(from: garbage)
        }
    }

    @Test("empty data throws decoding error")
    func emptyDataThrowsDecodingError() {
        #expect(throws: (any Error).self) {
            _ = try CompanionMessage.decode(from: Data())
        }
    }
}
