import Foundation
import Network
import Testing
@testable import NetMonitorCore

/// The device list across Mac and phone builds (#594 PR2, v3.1 §7), sent over the authenticated
/// companion link (#605): a list without `members` (a Mac before PR2) decodes on a new phone, and a
/// list with them decodes on an old phone, which ignores them.
@Suite("Companion device list: old and new builds", .serialized)
struct CompanionDeviceListCompatibilityTests {
    private let mac = CompanionIdentity()
    private let phone = CompanionIdentity()

    /// The device list as a phone before #594 PR2 decodes it: no `members`, no `isDeviceOnline`.
    private struct OldDeviceInfo: Decodable {
        let id: UUID
        let ipAddress: String
        let macAddress: String
        let hostname: String?
        let vendor: String?
        let deviceType: String
        let isOnline: Bool
    }

    private struct OldDeviceList: Decodable {
        let devices: [OldDeviceInfo]
    }

    private struct OldMessage: Decodable {
        let type: String
        let payload: OldDeviceList
    }

    /// What an old Mac sends: the frozen shape, with only the fields it knew.
    private struct OldDeviceInfoSent: Encodable {
        let id: UUID
        let ipAddress: String
        let macAddress: String
        let hostname: String?
        let vendor: String?
        let deviceType: String
        let isOnline: Bool
    }

    private struct OldMessageSent: Encodable {
        let protocolVersion = CompanionMessage.currentProtocolVersion
        let type = "deviceList"
        let payload: [String: [OldDeviceInfoSent]]
    }

    static let scan = Date(timeIntervalSince1970: 1_790_000_000)

    /// A device of two interfaces, the Wi-Fi one current and answering.
    static var newDevice: DeviceInfo {
        DeviceInfo(
            id: UUID(), ipAddress: "192.168.77.61", macAddress: "02:00:00:77:00:61", hostname: "studio", vendor: "Apple",
            deviceType: "computer", isOnline: true,
            members: [
                MemberInfo(
                    id: UUID(), ipAddress: "192.168.77.61", macAddress: "02:00:00:77:00:61", lastSeen: scan, answeredLatestScan: true, scanTime: scan
                ),
                MemberInfo(
                    id: UUID(), ipAddress: "192.168.77.60", macAddress: nil, lastSeen: scan.addingTimeInterval(-7200),
                    answeredLatestScan: false, scanTime: scan
                )
            ],
            isDeviceOnline: true
        )
    }

    /// Sends `frame` from the phone's side to the Mac's over a mutually pinned TLS link and returns
    /// the JSON of the one frame the other side received.
    private func sendOverLink(_ frame: Data) async throws -> Data {
        let harness = try await LoopbackHarness(server: mac, acceptsClient: { [phone] in $0 == phone.pin })
        defer { harness.stop() }
        let outcome = await harness.connect(client: phone, pinning: mac.pin, sending: frame)
        #expect(outcome.session != nil, "The link is authenticated")
        var received = Data()
        let deadline = ContinuousClock.now + .seconds(5)
        // Reads until the length prefix is satisfied (the first read may be partial).
        while ContinuousClock.now < deadline {
            received = await harness.nextServerBytes()
            if received.count >= 4 {
                let length = received.prefix(4).reduce(0) { $0 << 8 | Int($1) }
                if received.count >= 4 + length {
                    return received.subdata(in: 4..<(4 + length))
                }
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        Issue.record("The frame never arrived whole (\(received.count) bytes)")
        return Data()
    }

    @Test("A new Mac's list, with members, decodes on a new phone with every interface")
    func newToNew() async throws {
        let device = Self.newDevice
        let frame = try CompanionMessage.deviceList(DeviceListPayload(devices: [device])).encodeLengthPrefixed()
        let json = try await sendOverLink(frame)
        guard case let .deviceList(payload) = try CompanionMessage.decode(from: json) else {
            Issue.record("Expected a device list")
            return
        }
        let received = try #require(payload.devices.first)
        #expect(received.members == device.members)
        #expect(received.isDeviceOnline == true)
        #expect(received.ipAddress == device.ipAddress)
    }

    @Test("A new Mac's list decodes on an old phone, which reads the device's current interface")
    func newToOld() async throws {
        let device = Self.newDevice
        let frame = try CompanionMessage.deviceList(DeviceListPayload(devices: [device])).encodeLengthPrefixed()
        let json = try await sendOverLink(frame)
        let old = try JSONDecoder().decode(OldMessage.self, from: json)
        #expect(old.type == "deviceList")
        let received = try #require(old.payload.devices.first)
        #expect(old.payload.devices.count == 1, "One entry per device, not per interface")
        #expect(received.id == device.id)
        #expect(received.ipAddress == "192.168.77.61")
        #expect(received.macAddress == "02:00:00:77:00:61")
        #expect(received.isOnline)
    }

    @Test("An old Mac's list, without members, decodes on a new phone as one sighting")
    func oldToNew() async throws {
        let id = UUID()
        let sent = OldMessageSent(payload: ["devices": [OldDeviceInfoSent(
            id: id, ipAddress: "192.168.77.20", macAddress: "", hostname: "printer", vendor: nil, deviceType: "printer", isOnline: true
        )]])
        let body = try JSONEncoder().encode(sent)
        var length = UInt32(body.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(body)
        let json = try await sendOverLink(frame)
        guard case let .deviceList(payload) = try CompanionMessage.decode(from: json) else {
            Issue.record("Expected a device list")
            return
        }
        let received = try #require(payload.devices.first)
        #expect(received.id == id)
        #expect(received.members == nil)
        #expect(received.isDeviceOnline == nil)
        // The phone turns it into this scan's sighting of its one address, as before #594 PR2.
        let sightings = DeviceDiscoveryService.companionSightings(
            list: payload, receivedAt: Self.scan, macConnected: true, now: Self.scan, includes: { _ in true }, profileID: nil
        )
        #expect(sightings.devices.map(\.ipAddress) == ["192.168.77.20"])
        #expect(sightings.fresh)
    }
}
