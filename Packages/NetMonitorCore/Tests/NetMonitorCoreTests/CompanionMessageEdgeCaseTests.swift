import Foundation
import Testing
@testable import NetMonitorCore

/// Contract tests for CompanionMessage wire protocol edge cases.
///
/// Existing CompanionMessageTests.swift covers standard round-trips for all message
/// types. These tests focus on edge-case payloads: empty arrays, extreme numeric
/// values, empty strings, and multi-message framing correctness.
struct CompanionMessageEdgeCaseTests {

    private let fixedDate = Date(timeIntervalSinceReferenceDate: 1_000_000.0)

    // MARK: - Empty Collection Payloads

    @Test("Empty targetList and deviceList arrays round-trip correctly")
    func emptyCollectionsRoundTrip() throws {
        // targetList
        let msg1 = CompanionMessage.targetList(TargetListPayload(targets: []))
        let data1 = try CompanionMessage.jsonEncoder.encode(msg1)
        let decoded1 = try CompanionMessage.decode(from: data1)
        guard case .targetList(let p1) = decoded1 else {
            Issue.record("Expected .targetList")
            return
        }
        #expect(p1.targets.isEmpty)

        // deviceList
        let msg2 = CompanionMessage.deviceList(DeviceListPayload(devices: []))
        let data2 = try CompanionMessage.jsonEncoder.encode(msg2)
        let decoded2 = try CompanionMessage.decode(from: data2)
        guard case .deviceList(let p2) = decoded2 else {
            Issue.record("Expected .deviceList")
            return
        }
        #expect(p2.devices.isEmpty)
    }

    // MARK: - Extreme Numeric Values

    @Test("statusUpdate with zero and large counts round-trips")
    func statusUpdateExtremeValuesRoundTrip() throws {
        // Zeros
        let zeroPayload = StatusUpdatePayload(
            isMonitoring: false, onlineTargets: 0, offlineTargets: 0,
            averageLatency: nil, timestamp: fixedDate
        )
        let zeroMsg = CompanionMessage.statusUpdate(zeroPayload)
        let zeroData = try CompanionMessage.jsonEncoder.encode(zeroMsg)
        let zeroDecoded = try CompanionMessage.decode(from: zeroData)
        guard case .statusUpdate(let z) = zeroDecoded else {
            Issue.record("Expected .statusUpdate")
            return
        }
        #expect(z.onlineTargets == 0)
        #expect(z.averageLatency == nil)

        // Large values
        let largePayload = StatusUpdatePayload(
            isMonitoring: true, onlineTargets: 999_999, offlineTargets: 500_000,
            averageLatency: 99999.99, timestamp: fixedDate
        )
        let largeMsg = CompanionMessage.statusUpdate(largePayload)
        let largeData = try CompanionMessage.jsonEncoder.encode(largeMsg)
        let largeDecoded = try CompanionMessage.decode(from: largeData)
        guard case .statusUpdate(let l) = largeDecoded else {
            Issue.record("Expected .statusUpdate")
            return
        }
        #expect(l.onlineTargets == 999_999)
        guard let latency = l.averageLatency else { Issue.record("Expected non-nil averageLatency")
        return
        }
        #expect(abs(latency - 99999.99) < 0.01)
    }

    // MARK: - Empty String and Empty Dictionary Payloads

    @Test("command with empty parameters, error with empty fields, toolResult with empty result")
    func emptyStringPayloadsRoundTrip() throws {
        // command with empty dict
        let cmdPayload = CommandPayload(action: .ping, parameters: [:])
        let cmdMsg = CompanionMessage.command(cmdPayload)
        let cmdDecoded = try CompanionMessage.decode(from: CompanionMessage.jsonEncoder.encode(cmdMsg))
        guard case .command(let c) = cmdDecoded else { Issue.record("Expected .command")
        return
        }
        #expect(c.parameters?.isEmpty == true)

        // error with empty fields
        let errPayload = ErrorPayload(code: "", message: "", timestamp: fixedDate)
        let errMsg = CompanionMessage.error(errPayload)
        let errDecoded = try CompanionMessage.decode(from: CompanionMessage.jsonEncoder.encode(errMsg))
        guard case .error(let e) = errDecoded else { Issue.record("Expected .error")
        return
        }
        #expect(e.code.isEmpty)
        #expect(e.message.isEmpty)

        // toolResult with empty result
        let trPayload = ToolResultPayload(tool: "ping", success: true, result: "", timestamp: fixedDate)
        let trMsg = CompanionMessage.toolResult(trPayload)
        let trDecoded = try CompanionMessage.decode(from: CompanionMessage.jsonEncoder.encode(trMsg))
        guard case .toolResult(let t) = trDecoded else { Issue.record("Expected .toolResult")
        return
        }
        #expect(t.result.isEmpty)
    }

    // MARK: - All-Nil Optional Fields

    @Test("deviceInfo and targetInfo with all optional fields nil round-trip")
    func allNilOptionalsRoundTrip() throws {
        // deviceInfo
        let device = DeviceInfo(
            id: UUID(), ipAddress: "10.0.0.1", macAddress: "00:00:00:00:00:00",
            hostname: nil, vendor: nil, deviceType: "unknown", isOnline: false
        )
        let devMsg = CompanionMessage.deviceList(DeviceListPayload(devices: [device]))
        let devDecoded = try CompanionMessage.decode(from: CompanionMessage.jsonEncoder.encode(devMsg))
        guard case .deviceList(let dp) = devDecoded else { Issue.record("Expected .deviceList")
        return
        }
        #expect(dp.devices[0].hostname == nil)
        #expect(dp.devices[0].vendor == nil)

        // targetInfo
        let target = TargetInfo(
            id: UUID(), name: "Test", host: "10.0.0.1", port: nil,
            protocol: "icmp", isEnabled: true, isReachable: nil, latency: nil
        )
        let tgtMsg = CompanionMessage.targetList(TargetListPayload(targets: [target]))
        let tgtDecoded = try CompanionMessage.decode(from: CompanionMessage.jsonEncoder.encode(tgtMsg))
        guard case .targetList(let tp) = tgtDecoded else { Issue.record("Expected .targetList")
        return
        }
        #expect(tp.targets[0].port == nil)
        #expect(tp.targets[0].isReachable == nil)
        #expect(tp.targets[0].latency == nil)
    }

    // MARK: - NetworkProfile with Empty Strings

    @Test("networkProfile with empty strings round-trips without data loss")
    func networkProfileEmptyStringsRoundTrip() throws {
        let payload = NetworkProfilePayload(
            name: "", gatewayIP: "", subnet: "", interfaceName: "", sourceDeviceName: nil
        )
        let msg = CompanionMessage.networkProfile(payload)
        let decoded = try CompanionMessage.decode(from: CompanionMessage.jsonEncoder.encode(msg))
        guard case .networkProfile(let p) = decoded else { Issue.record("Expected .networkProfile")
        return
        }
        #expect(p.name == "")
        #expect(p.gatewayIP == "")
        #expect(p.sourceDeviceName == nil)
    }

    // MARK: - Multiple Messages in Sequence

    @Test("Multiple length-prefixed messages concatenated can be decoded individually")
    func multipleLengthPrefixedMessagesDecodable() throws {
        let msg1 = CompanionMessage.heartbeat(HeartbeatPayload(timestamp: fixedDate, version: "2.0"))
        let msg2 = CompanionMessage.command(CommandPayload(action: .stopMonitoring))

        let frame1 = try msg1.encodeLengthPrefixed()
        let frame2 = try msg2.encodeLengthPrefixed()

        var combined = Data()
        combined.append(frame1)
        combined.append(frame2)

        // Extract first message
        let len1 = frame1.prefix(4).withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let json1 = combined[4..<(4 + Int(len1))]
        let decoded1 = try CompanionMessage.decode(from: Data(json1))
        guard case .heartbeat(let h) = decoded1 else {
            Issue.record("Expected .heartbeat")
            return
        }
        #expect(h.version == "2.0")

        // Extract second message
        let offset = 4 + Int(len1)
        let len2 = combined[offset..<(offset + 4)].withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
        let json2 = combined[(offset + 4)..<(offset + 4 + Int(len2))]
        let decoded2 = try CompanionMessage.decode(from: Data(json2))
        guard case .command(let c) = decoded2 else {
            Issue.record("Expected .command")
            return
        }
        #expect(c.action == .stopMonitoring)
    }

    // MARK: - Unicode in Payloads

    @Test("Device hostname with Unicode characters round-trips correctly")
    func unicodeHostnameRoundTrip() throws {
        let device = DeviceInfo(
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "Blake\u{2019}s-MacBook-\u{1F4BB}",
            isOnline: true
        )
        let msg = CompanionMessage.deviceList(DeviceListPayload(devices: [device]))
        let data = try CompanionMessage.jsonEncoder.encode(msg)
        let decoded = try CompanionMessage.decode(from: data)
        guard case .deviceList(let p) = decoded else {
            Issue.record("Expected .deviceList")
            return
        }
        #expect(p.devices[0].hostname == "Blake\u{2019}s-MacBook-\u{1F4BB}")
    }
}
