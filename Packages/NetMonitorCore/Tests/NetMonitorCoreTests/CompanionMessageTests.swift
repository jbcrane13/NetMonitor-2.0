import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Helpers

private let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000_000.0)

// MARK: - Codable Round-Trip

struct CompanionMessageCodableTests {
    @Test func heartbeatRoundTrip() throws {
        let payload = HeartbeatPayload(timestamp: fixedDate, version: "2.0")
        let msg = CompanionMessage.heartbeat(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .heartbeat(let received) = decoded else {
            Issue.record("Expected .heartbeat, got different case")
            return
        }
        #expect(received.version == "2.0")
        #expect(abs(received.timestamp.timeIntervalSince(fixedDate)) < 0.001)
    }

    @Test func statusUpdateRoundTrip() throws {
        let payload = StatusUpdatePayload(
            isMonitoring: true,
            onlineTargets: 5,
            offlineTargets: 2,
            averageLatency: 42.5,
            timestamp: fixedDate
        )
        let msg = CompanionMessage.statusUpdate(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .statusUpdate(let received) = decoded else {
            Issue.record("Expected .statusUpdate")
            return
        }
        #expect(received.isMonitoring == true)
        #expect(received.onlineTargets == 5)
        #expect(received.offlineTargets == 2)
        #expect(received.averageLatency == 42.5)
    }

    @Test func statusUpdateWithNilLatencyRoundTrip() throws {
        let payload = StatusUpdatePayload(
            isMonitoring: false,
            onlineTargets: 0,
            offlineTargets: 3,
            averageLatency: nil,
            timestamp: fixedDate
        )
        let msg = CompanionMessage.statusUpdate(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .statusUpdate(let received) = decoded else {
            Issue.record("Expected .statusUpdate")
            return
        }
        #expect(received.averageLatency == nil)
        #expect(received.isMonitoring == false)
    }

    @Test func targetListRoundTrip() throws {
        let target = TargetInfo(
            id: UUID(),
            name: "Google DNS",
            host: "8.8.8.8",
            port: nil,
            protocol: "icmp",
            isEnabled: true,
            isReachable: true,
            latency: 12.3
        )
        let payload = TargetListPayload(targets: [target])
        let msg = CompanionMessage.targetList(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .targetList(let received) = decoded else {
            Issue.record("Expected .targetList")
            return
        }
        #expect(received.targets.count == 1)
        #expect(received.targets[0].name == "Google DNS")
        #expect(received.targets[0].host == "8.8.8.8")
        #expect(received.targets[0].port == nil)
        #expect(received.targets[0].isEnabled == true)
        #expect(received.targets[0].isReachable == true)
        #expect(received.targets[0].latency == 12.3)
    }

    @Test func deviceListRoundTrip() throws {
        let device = DeviceInfo(
            id: UUID(),
            ipAddress: "192.168.1.100",
            macAddress: "aa:bb:cc:dd:ee:ff",
            hostname: "myphone",
            vendor: "Apple",
            deviceType: "phone",
            isOnline: true
        )
        let payload = DeviceListPayload(devices: [device])
        let msg = CompanionMessage.deviceList(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .deviceList(let received) = decoded else {
            Issue.record("Expected .deviceList")
            return
        }
        #expect(received.devices.count == 1)
        #expect(received.devices[0].ipAddress == "192.168.1.100")
        #expect(received.devices[0].macAddress == "aa:bb:cc:dd:ee:ff")
        #expect(received.devices[0].hostname == "myphone")
        #expect(received.devices[0].vendor == "Apple")
        #expect(received.devices[0].isOnline == true)
    }

    @Test func networkProfileRoundTrip() throws {
        let payload = NetworkProfilePayload(
            name: "Office LAN",
            gatewayIP: "10.10.0.1",
            subnet: "10.10.0.0/24",
            interfaceName: "en0",
            sourceDeviceName: "Blake's MacBook Pro"
        )
        let msg = CompanionMessage.networkProfile(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .networkProfile(let received) = decoded else {
            Issue.record("Expected .networkProfile")
            return
        }
        #expect(received.name == "Office LAN")
        #expect(received.gatewayIP == "10.10.0.1")
        #expect(received.subnet == "10.10.0.0/24")
        #expect(received.interfaceName == "en0")
        #expect(received.sourceDeviceName == "Blake's MacBook Pro")
    }

    @Test func commandRoundTrip() throws {
        let payload = CommandPayload(action: .scanDevices, parameters: ["subnet": "192.168.1.0/24"])
        let msg = CompanionMessage.command(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .command(let received) = decoded else {
            Issue.record("Expected .command")
            return
        }
        #expect(received.action == .scanDevices)
        #expect(received.parameters?["subnet"] == "192.168.1.0/24")
    }

    @Test func commandWithNilParametersRoundTrip() throws {
        let payload = CommandPayload(action: .startMonitoring)
        let msg = CompanionMessage.command(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .command(let received) = decoded else {
            Issue.record("Expected .command")
            return
        }
        #expect(received.action == .startMonitoring)
        #expect(received.parameters == nil)
    }

    @Test func toolResultRoundTrip() throws {
        let payload = ToolResultPayload(tool: "ping", success: true, result: "64 bytes from 8.8.8.8", timestamp: fixedDate)
        let msg = CompanionMessage.toolResult(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .toolResult(let received) = decoded else {
            Issue.record("Expected .toolResult")
            return
        }
        #expect(received.tool == "ping")
        #expect(received.success == true)
        #expect(received.result == "64 bytes from 8.8.8.8")
    }

    @Test func errorRoundTrip() throws {
        let payload = ErrorPayload(code: "ERR_001", message: "Something went wrong", timestamp: fixedDate)
        let msg = CompanionMessage.error(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .error(let received) = decoded else {
            Issue.record("Expected .error")
            return
        }
        #expect(received.code == "ERR_001")
        #expect(received.message == "Something went wrong")
    }
}

// MARK: - Length-Prefixed Framing

struct CompanionMessageLengthPrefixedTests {
    @Test func prefixMatchesJSONPayloadLength() throws {
        let payload = HeartbeatPayload(timestamp: fixedDate, version: "1.0")
        let msg = CompanionMessage.heartbeat(payload)
        let framed = try msg.encodeLengthPrefixed()

        // Must have at least 4 bytes for the length prefix
        #expect(framed.count > 4)

        // Extract the 4-byte big-endian length
        let prefixBytes = framed.prefix(4)
        let length = prefixBytes.withUnsafeBytes { bytes in
            bytes.load(as: UInt32.self).bigEndian
        }
        let jsonData = framed.dropFirst(4)

        #expect(Int(length) == jsonData.count)
        #expect(framed.count == 4 + Int(length))
    }

    @Test func jsonPayloadDecodesCorrectly() throws {
        let payload = HeartbeatPayload(timestamp: fixedDate, version: "1.0")
        let msg = CompanionMessage.heartbeat(payload)
        let framed = try msg.encodeLengthPrefixed()

        let jsonData = framed.dropFirst(4)
        let decoded = try CompanionMessage.decode(from: Data(jsonData))
        guard case .heartbeat(let received) = decoded else {
            Issue.record("Expected .heartbeat")
            return
        }
        #expect(received.version == "1.0")
    }

    @Test func differentMessagesProduceDifferentLengths() throws {
        let shortMsg = CompanionMessage.heartbeat(HeartbeatPayload(version: "1"))
        let longMsg = CompanionMessage.deviceList(DeviceListPayload(devices: [
            DeviceInfo(ipAddress: "192.168.1.1", macAddress: "aa:bb:cc:dd:ee:ff", hostname: "long-hostname-device", isOnline: true),
            DeviceInfo(ipAddress: "192.168.1.2", macAddress: "11:22:33:44:55:66", hostname: "another-device", isOnline: false)
        ]))
        let shortFramed = try shortMsg.encodeLengthPrefixed()
        let longFramed = try longMsg.encodeLengthPrefixed()
        #expect(shortFramed.count < longFramed.count)
    }
}

// MARK: - CommandAction Coverage

struct CommandActionTests {
    @Test func allCommandActionsEncodeAndDecodeRoundTrip() throws {
        let actions: [CommandAction] = [
            .startMonitoring, .stopMonitoring, .scanDevices,
            .ping, .traceroute, .portScan, .dnsLookup,
            .wakeOnLan, .refreshTargets, .refreshDevices
        ]
        for action in actions {
            let payload = CommandPayload(action: action)
            let msg = CompanionMessage.command(payload)
            let data = try CompanionMessage.jsonEncoder.encode(msg)
            let decoded = try CompanionMessage.decode(from: data)
            guard case .command(let received) = decoded else {
                Issue.record("Expected .command for action \(action)")
                continue
            }
            #expect(received.action == action)
        }
    }
}

// MARK: - CompanionMessage Additional Cases

struct CompanionMessageAdditionalCasesTests {

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000_000.0)

    // MARK: - ToolResult Payload

    @Test func toolResultFailureRoundTrip() throws {
        let payload = ToolResultPayload(tool: "traceroute", success: false, result: "Timeout", timestamp: fixedDate)
        let msg = CompanionMessage.toolResult(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .toolResult(let received) = decoded else {
            Issue.record("Expected .toolResult")
            return
        }
        #expect(received.tool == "traceroute")
        #expect(received.success == false)
        #expect(received.result == "Timeout")
        #expect(abs(received.timestamp.timeIntervalSince(fixedDate)) < 0.001)
    }

    // MARK: - Error Payload

    @Test func errorPayloadWithKnownCodeRoundTrip() throws {
        let payload = ErrorPayload(code: "MISSING_PARAMETER", message: "host is required", timestamp: fixedDate)
        let msg = CompanionMessage.error(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .error(let received) = decoded else {
            Issue.record("Expected .error")
            return
        }
        #expect(received.code == "MISSING_PARAMETER")
        #expect(received.message == "host is required")
    }

    // MARK: - NetworkProfile Payload

    @Test func networkProfileWithNilSourceDeviceNameRoundTrip() throws {
        let payload = NetworkProfilePayload(
            name: "Home Network",
            gatewayIP: "192.168.0.1",
            subnet: "192.168.0.0/24",
            interfaceName: "en1",
            sourceDeviceName: nil
        )
        let msg = CompanionMessage.networkProfile(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .networkProfile(let received) = decoded else {
            Issue.record("Expected .networkProfile")
            return
        }
        #expect(received.name == "Home Network")
        #expect(received.gatewayIP == "192.168.0.1")
        #expect(received.subnet == "192.168.0.0/24")
        #expect(received.interfaceName == "en1")
        #expect(received.sourceDeviceName == nil)
    }

    // MARK: - TargetList with multiple targets

    @Test func targetListWithMultipleTargetsRoundTrip() throws {
        let targets = [
            TargetInfo(id: UUID(), name: "DNS", host: "8.8.8.8", port: nil, protocol: "icmp",
                       isEnabled: true, isReachable: true, latency: 5.0),
            TargetInfo(id: UUID(), name: "HTTP", host: "example.com", port: 80, protocol: "tcp",
                       isEnabled: false, isReachable: nil, latency: nil),
        ]
        let msg = CompanionMessage.targetList(TargetListPayload(targets: targets))
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .targetList(let received) = decoded else {
            Issue.record("Expected .targetList")
            return
        }
        #expect(received.targets.count == 2)
        let http = received.targets.first { $0.name == "HTTP" }
        #expect(http?.port == 80)
        #expect(http?.isEnabled == false)
        #expect(http?.isReachable == nil)
        #expect(http?.latency == nil)
    }

    // MARK: - DeviceList with nil optional fields

    @Test func deviceListWithNilHostnameAndVendorRoundTrip() throws {
        let device = DeviceInfo(
            id: UUID(),
            ipAddress: "10.0.0.5",
            macAddress: "DE:AD:BE:EF:00:01",
            hostname: nil,
            vendor: nil,
            deviceType: "router",
            isOnline: true
        )
        let msg = CompanionMessage.deviceList(DeviceListPayload(devices: [device]))
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .deviceList(let received) = decoded else {
            Issue.record("Expected .deviceList")
            return
        }
        #expect(received.devices.count == 1)
        #expect(received.devices[0].hostname == nil)
        #expect(received.devices[0].vendor == nil)
        #expect(received.devices[0].ipAddress == "10.0.0.5")
    }

    // MARK: - Protocol Version

    @Test func encodedMessageIncludesProtocolVersion() throws {
        let msg = CompanionMessage.heartbeat(HeartbeatPayload(version: "2.0"))
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["protocolVersion"] as? Int == CompanionMessage.currentProtocolVersion)
    }

    @Test func decodeThrowsVersionMismatchForUnsupportedProtocolVersion() {
        let unsupportedVersion = CompanionMessage.currentProtocolVersion + 1
        let json = """
        {
          "protocolVersion": \(unsupportedVersion),
          "type": "heartbeat",
          "payload": {
            "timestamp": "2026-05-18T00:00:00Z",
            "version": "2.0"
          }
        }
        """

        #expect(throws: CompanionMessageDecodeError.versionMismatch(got: unsupportedVersion, expected: CompanionMessage.currentProtocolVersion)) {
            _ = try CompanionMessage.decode(from: Data(json.utf8))
        }
    }

    // MARK: - Malformed JSON

    @Test func malformedJsonThrowsDecodingError() {
        let badData = Data("{ \"payload\": {} ".utf8)
        #expect(throws: (any Error).self) {
            _ = try CompanionMessage.decode(from: badData)
        }
    }

    /// A type from a newer peer is kept as `.unknown`, not a decode error (Models/AGENTS.md, #457).
    @Test func unknownTypeDecodesAsUnknown() throws {
        let data = Data("{ \"type\": \"unknownType\", \"payload\": {} }".utf8)
        guard case let .unknown(type) = try CompanionMessage.decode(from: data) else {
            Issue.record("expected .unknown")
            return
        }
        #expect(type == "unknownType")
    }

    @Test func emptyJsonObjectThrowsDecodingError() {
        let badData = Data("{}".utf8)
        #expect(throws: (any Error).self) {
            _ = try CompanionMessage.decode(from: badData)
        }
    }
}
