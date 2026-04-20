import Testing
import Foundation
import NetMonitorCore

// MARK: - Companion Message Contract Tests

/// Contract tests for CompanionMessage payload fidelity — validates that every
/// field in each payload type survives encode → decode without data loss.
///
/// CompanionWireProtocolTests covers framing (length-prefix), JSON wire shape
/// ({type, payload}), error cases, and special characters. These tests focus on
/// gaps: field-level payload verification, cross-platform date stability,
/// DeviceInfo/TargetInfo full-field round-trips, CommandAction exhaustive coverage,
/// and large payload handling.
struct CompanionMessageContractTests {

    // MARK: - DeviceInfo Full-Field Round-Trip

    @Test("deviceList with fully-populated DeviceInfo preserves all fields")
    func deviceInfoFullFieldRoundTrip() throws {
        let deviceID = UUID()
        let device = DeviceInfo(
            id: deviceID,
            ipAddress: "192.168.1.42",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "blake-macbook.local",
            vendor: "Apple, Inc.",
            deviceType: "computer",
            isOnline: true
        )

        let message = CompanionMessage.deviceList(DeviceListPayload(devices: [device]))
        let data = try CompanionMessage.jsonEncoder.encode(message)
        let decoded = try CompanionMessage.decode(from: data)

        guard case .deviceList(let payload) = decoded else {
            Issue.record("Expected deviceList, got different message type")
            return
        }

        #expect(payload.devices.count == 1)
        let d = payload.devices[0]
        #expect(d.id == deviceID)
        #expect(d.ipAddress == "192.168.1.42")
        #expect(d.macAddress == "AA:BB:CC:DD:EE:FF")
        #expect(d.hostname == "blake-macbook.local")
        #expect(d.vendor == "Apple, Inc.")
        #expect(d.deviceType == "computer")
        #expect(d.isOnline == true)
    }

    @Test("deviceList with nil optional fields preserves nil values")
    func deviceInfoNilFieldsRoundTrip() throws {
        let device = DeviceInfo(
            ipAddress: "10.0.0.1",
            macAddress: "00:00:00:00:00:00",
            hostname: nil,
            vendor: nil,
            deviceType: "unknown",
            isOnline: false
        )

        let message = CompanionMessage.deviceList(DeviceListPayload(devices: [device]))
        let data = try CompanionMessage.jsonEncoder.encode(message)
        let decoded = try CompanionMessage.decode(from: data)

        guard case .deviceList(let payload) = decoded else {
            Issue.record("Expected deviceList")
            return
        }

        let d = payload.devices[0]
        #expect(d.hostname == nil)
        #expect(d.vendor == nil)
        #expect(d.isOnline == false)
    }

    // MARK: - TargetInfo Full-Field Round-Trip

    @Test("targetList with fully-populated TargetInfo preserves all fields")
    func targetInfoFullFieldRoundTrip() throws {
        let targetID = UUID()
        let target = TargetInfo(
            id: targetID,
            name: "Google DNS",
            host: "8.8.8.8",
            port: 53,
            protocol: "ICMP",
            isEnabled: true,
            isReachable: true,
            latency: 12.5
        )

        let message = CompanionMessage.targetList(TargetListPayload(targets: [target]))
        let data = try CompanionMessage.jsonEncoder.encode(message)
        let decoded = try CompanionMessage.decode(from: data)

        guard case .targetList(let payload) = decoded else {
            Issue.record("Expected targetList")
            return
        }

        #expect(payload.targets.count == 1)
        let t = payload.targets[0]
        #expect(t.id == targetID)
        #expect(t.name == "Google DNS")
        #expect(t.host == "8.8.8.8")
        #expect(t.port == 53)
        #expect(t.protocol == "ICMP")
        #expect(t.isEnabled == true)
        #expect(t.isReachable == true)
        #expect(t.latency == 12.5)
    }

    @Test("targetList with nil optional fields preserves nil values")
    func targetInfoNilOptionals() throws {
        let target = TargetInfo(
            id: UUID(),
            name: "Test",
            host: "example.com",
            port: nil,
            protocol: "TCP",
            isEnabled: false,
            isReachable: nil,
            latency: nil
        )

        let message = CompanionMessage.targetList(TargetListPayload(targets: [target]))
        let data = try CompanionMessage.jsonEncoder.encode(message)
        let decoded = try CompanionMessage.decode(from: data)

        guard case .targetList(let payload) = decoded else {
            Issue.record("Expected targetList")
            return
        }

        let t = payload.targets[0]
        #expect(t.port == nil)
        #expect(t.isReachable == nil)
        #expect(t.latency == nil)
    }

    // MARK: - StatusUpdate Payload Fidelity

    @Test("statusUpdate preserves all fields including nil averageLatency")
    func statusUpdateFullFields() throws {
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

        let message = CompanionMessage.statusUpdate(StatusUpdatePayload(
            isMonitoring: true,
            onlineTargets: 5,
            offlineTargets: 2,
            averageLatency: nil,
            timestamp: timestamp
        ))

        let data = try CompanionMessage.jsonEncoder.encode(message)
        let decoded = try CompanionMessage.decode(from: data)

        guard case .statusUpdate(let payload) = decoded else {
            Issue.record("Expected statusUpdate")
            return
        }

        #expect(payload.isMonitoring == true)
        #expect(payload.onlineTargets == 5)
        #expect(payload.offlineTargets == 2)
        #expect(payload.averageLatency == nil)
        #expect(payload.timestamp == timestamp)
    }

    // MARK: - All CommandAction Values

    @Test("Every CommandAction case survives round-trip through command message")
    func allCommandActionsRoundTrip() throws {
        let allActions: [CommandAction] = [
            .startMonitoring, .stopMonitoring, .scanDevices,
            .ping, .traceroute, .portScan, .dnsLookup,
            .wakeOnLan, .refreshTargets, .refreshDevices
        ]

        for action in allActions {
            let message = CompanionMessage.command(CommandPayload(
                action: action,
                parameters: ["target": "192.168.1.1"]
            ))

            let data = try CompanionMessage.jsonEncoder.encode(message)
            let decoded = try CompanionMessage.decode(from: data)

            guard case .command(let payload) = decoded else {
                Issue.record("Expected command for action \(action)")
                continue
            }

            #expect(payload.action == action, "CommandAction.\(action) failed round-trip")
            #expect(payload.parameters?["target"] == "192.168.1.1")
        }
    }

    // MARK: - NetworkProfile Full Fields

    @Test("networkProfile with sourceDeviceName preserves all fields")
    func networkProfileFullFields() throws {
        let message = CompanionMessage.networkProfile(NetworkProfilePayload(
            name: "Home Network",
            gatewayIP: "192.168.1.1",
            subnet: "255.255.255.0",
            interfaceName: "en0",
            sourceDeviceName: "Blake's Mac mini"
        ))

        let data = try CompanionMessage.jsonEncoder.encode(message)
        let decoded = try CompanionMessage.decode(from: data)

        guard case .networkProfile(let payload) = decoded else {
            Issue.record("Expected networkProfile")
            return
        }

        #expect(payload.name == "Home Network")
        #expect(payload.gatewayIP == "192.168.1.1")
        #expect(payload.subnet == "255.255.255.0")
        #expect(payload.interfaceName == "en0")
        #expect(payload.sourceDeviceName == "Blake's Mac mini")
    }

    // MARK: - Large Payload Handling

    @Test("deviceList with 100 devices encodes and decodes correctly")
    func largeDeviceList() throws {
        let devices = (0..<100).map { i in
            DeviceInfo(
                ipAddress: "192.168.1.\(i)",
                macAddress: String(format: "AA:BB:CC:DD:%02X:%02X", i / 256, i % 256),
                hostname: "device-\(i).local",
                isOnline: i % 3 != 0
            )
        }

        let message = CompanionMessage.deviceList(DeviceListPayload(devices: devices))
        let data = try CompanionMessage.jsonEncoder.encode(message)
        let decoded = try CompanionMessage.decode(from: data)

        guard case .deviceList(let payload) = decoded else {
            Issue.record("Expected deviceList")
            return
        }

        #expect(payload.devices.count == 100)
        #expect(payload.devices[0].ipAddress == "192.168.1.0")
        #expect(payload.devices[99].ipAddress == "192.168.1.99")
        // Verify online/offline pattern survived
        #expect(payload.devices[0].isOnline == false, "i=0 should be offline (0 % 3 == 0)")
        #expect(payload.devices[1].isOnline == true)
        #expect(payload.devices[3].isOnline == false, "i=3 should be offline (3 % 3 == 0)")
    }

    // MARK: - Date Encoding Stability

    @Test("Dates in toolResult and error payloads use consistent encoding")
    func dateEncodingConsistency() throws {
        let fixedDate = Date(timeIntervalSince1970: 1_712_000_000)

        let toolMsg = CompanionMessage.toolResult(ToolResultPayload(
            tool: "ping",
            success: true,
            result: "64 bytes from 8.8.8.8: time=12ms",
            timestamp: fixedDate
        ))

        let errorMsg = CompanionMessage.error(ErrorPayload(
            code: "TIMEOUT",
            message: "Connection timed out",
            timestamp: fixedDate
        ))

        let toolData = try CompanionMessage.jsonEncoder.encode(toolMsg)
        let errorData = try CompanionMessage.jsonEncoder.encode(errorMsg)

        let decodedTool = try CompanionMessage.decode(from: toolData)
        let decodedError = try CompanionMessage.decode(from: errorData)

        guard case .toolResult(let toolPayload) = decodedTool,
              case .error(let errorPayload) = decodedError else {
            Issue.record("Unexpected message types")
            return
        }

        // Both timestamps should decode to the exact same date
        #expect(toolPayload.timestamp == fixedDate)
        #expect(errorPayload.timestamp == fixedDate)
        #expect(toolPayload.timestamp == errorPayload.timestamp,
                "Same Date value must produce identical encoding across payload types")
    }
}
