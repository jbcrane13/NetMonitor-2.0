import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Helpers

private let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000_000.0)

// MARK: - Codable Round-Trip

@Suite("CompanionMessage Codable Round-Trip")
struct CompanionMessageCodableTests {
    @Test func heartbeatRoundTrip() throws {
        let payload = HeartbeatPayload(timestamp: fixedDate, version: "2.0")
        let msg = CompanionMessage.heartbeat(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .heartbeat(let p) = decoded else {
            Issue.record("Expected .heartbeat, got different case")
            return
        }
        #expect(p.version == "2.0")
        #expect(abs(p.timestamp.timeIntervalSince(fixedDate)) < 0.001)
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
        guard case .statusUpdate(let p) = decoded else {
            Issue.record("Expected .statusUpdate")
            return
        }
        #expect(p.isMonitoring == true)
        #expect(p.onlineTargets == 5)
        #expect(p.offlineTargets == 2)
        #expect(p.averageLatency == 42.5)
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
        guard case .statusUpdate(let p) = decoded else {
            Issue.record("Expected .statusUpdate")
            return
        }
        #expect(p.averageLatency == nil)
        #expect(p.isMonitoring == false)
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
        guard case .targetList(let p) = decoded else {
            Issue.record("Expected .targetList")
            return
        }
        #expect(p.targets.count == 1)
        #expect(p.targets[0].name == "Google DNS")
        #expect(p.targets[0].host == "8.8.8.8")
        #expect(p.targets[0].port == nil)
        #expect(p.targets[0].isEnabled == true)
        #expect(p.targets[0].isReachable == true)
        #expect(p.targets[0].latency == 12.3)
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
        guard case .deviceList(let p) = decoded else {
            Issue.record("Expected .deviceList")
            return
        }
        #expect(p.devices.count == 1)
        #expect(p.devices[0].ipAddress == "192.168.1.100")
        #expect(p.devices[0].macAddress == "aa:bb:cc:dd:ee:ff")
        #expect(p.devices[0].hostname == "myphone")
        #expect(p.devices[0].vendor == "Apple")
        #expect(p.devices[0].isOnline == true)
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
        guard case .networkProfile(let p) = decoded else {
            Issue.record("Expected .networkProfile")
            return
        }
        #expect(p.name == "Office LAN")
        #expect(p.gatewayIP == "10.10.0.1")
        #expect(p.subnet == "10.10.0.0/24")
        #expect(p.interfaceName == "en0")
        #expect(p.sourceDeviceName == "Blake's MacBook Pro")
    }

    @Test func commandRoundTrip() throws {
        let payload = CommandPayload(action: .scanDevices, parameters: ["subnet": "192.168.1.0/24"])
        let msg = CompanionMessage.command(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .command(let p) = decoded else {
            Issue.record("Expected .command")
            return
        }
        #expect(p.action == .scanDevices)
        #expect(p.parameters?["subnet"] == "192.168.1.0/24")
    }

    @Test func commandWithNilParametersRoundTrip() throws {
        let payload = CommandPayload(action: .startMonitoring)
        let msg = CompanionMessage.command(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .command(let p) = decoded else {
            Issue.record("Expected .command")
            return
        }
        #expect(p.action == .startMonitoring)
        #expect(p.parameters == nil)
    }

    @Test func toolResultRoundTrip() throws {
        let payload = ToolResultPayload(tool: "ping", success: true, result: "64 bytes from 8.8.8.8", timestamp: fixedDate)
        let msg = CompanionMessage.toolResult(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .toolResult(let p) = decoded else {
            Issue.record("Expected .toolResult")
            return
        }
        #expect(p.tool == "ping")
        #expect(p.success == true)
        #expect(p.result == "64 bytes from 8.8.8.8")
    }

    @Test func errorRoundTrip() throws {
        let payload = ErrorPayload(code: "ERR_001", message: "Something went wrong", timestamp: fixedDate)
        let msg = CompanionMessage.error(payload)
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .error(let p) = decoded else {
            Issue.record("Expected .error")
            return
        }
        #expect(p.code == "ERR_001")
        #expect(p.message == "Something went wrong")
    }
}

// MARK: - Length-Prefixed Framing

@Suite("CompanionMessage.encodeLengthPrefixed")
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
        guard case .heartbeat(let p) = decoded else {
            Issue.record("Expected .heartbeat")
            return
        }
        #expect(p.version == "1.0")
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

@Suite("CommandAction")
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
            guard case .command(let p) = decoded else {
                Issue.record("Expected .command for action \(action)")
                continue
            }
            #expect(p.action == action)
        }
    }
}
