import Testing
import Foundation
import NetMonitorCore
@testable import NetMonitor_iOS

/// MacConnectionService tests covering logic NOT in MacConnectionServiceReceiveBufferTests.
///
/// INTEGRATION GAP: NWConnection, NWBrowser, and NWEndpoint require real
/// network stack access. These tests cover message serialization/deserialization,
/// state transitions on the shared singleton, and displayText formatting.

@MainActor
struct MacConnectionServiceTests {

    // MARK: - MacConnectionState

    @Test("MacConnectionState.isConnected returns true only for .connected")
    func isConnectedProperty() {
        #expect(MacConnectionState.connected.isConnected == true)
        #expect(MacConnectionState.disconnected.isConnected == false)
        #expect(MacConnectionState.browsing.isConnected == false)
        #expect(MacConnectionState.connecting.isConnected == false)
        #expect(MacConnectionState.error("test").isConnected == false)
    }

    @Test("MacConnectionState.displayText returns correct strings")
    func displayTextValues() {
        #expect(MacConnectionState.disconnected.displayText == "Disconnected")
        #expect(MacConnectionState.browsing.displayText.contains("Browsing"))
        #expect(MacConnectionState.connecting.displayText.contains("Connecting"))
        #expect(MacConnectionState.connected.displayText == "Connected")
        #expect(MacConnectionState.error("fail").displayText == "Error: fail")
    }

    @Test("MacConnectionState equatable works for error case")
    func stateEquatable() {
        #expect(MacConnectionState.error("a") == MacConnectionState.error("a"))
        #expect(MacConnectionState.error("a") != MacConnectionState.error("b"))
        #expect(MacConnectionState.connected == MacConnectionState.connected)
        #expect(MacConnectionState.disconnected != MacConnectionState.connected)
    }

    // MARK: - Disconnect resets state

    @Test("disconnect resets all connection state")
    func disconnectResetsState() {
        let service = MacConnectionService.shared
        service.disconnect()

        #expect(service.connectionState == .disconnected)
        #expect(service.connectedMacName == nil)
        #expect(service.lastStatusUpdate == nil)
        #expect(service.lastDeviceList == nil)
    }

    @Test("disconnect is idempotent")
    func disconnectIdempotent() {
        let service = MacConnectionService.shared
        service.disconnect()
        service.disconnect()
        service.disconnect()

        #expect(service.connectionState == .disconnected)
    }

    // MARK: - CompanionMessage serialization

    @Test("CompanionMessage.statusUpdate round-trips through encodeLengthPrefixed and decode")
    func statusUpdateRoundTrips() throws {
        let payload = StatusUpdatePayload(
            isMonitoring: true,
            onlineTargets: 5,
            offlineTargets: 2,
            averageLatency: 15.5
        )
        let message = CompanionMessage.statusUpdate(payload)
        let data = try message.encodeLengthPrefixed()

        // Verify length prefix (first 4 bytes)
        #expect(data.count > 4)
        let length = UInt32(data[0]) << 24 | UInt32(data[1]) << 16 | UInt32(data[2]) << 8 | UInt32(data[3])
        #expect(Int(length) == data.count - 4)

        // Decode the JSON portion
        let jsonData = data.subdata(in: 4..<data.count)
        let decoded = try CompanionMessage.decode(from: jsonData)

        if case .statusUpdate(let decodedPayload) = decoded {
            #expect(decodedPayload.isMonitoring == true)
            #expect(decodedPayload.onlineTargets == 5)
            #expect(decodedPayload.offlineTargets == 2)
            #expect(decodedPayload.averageLatency == 15.5)
        } else {
            #expect(Bool(false), "Expected statusUpdate message, got \(decoded)")
        }
    }

    @Test("CompanionMessage.heartbeat round-trips correctly")
    func heartbeatRoundTrips() throws {
        let now = Date()
        let message = CompanionMessage.heartbeat(HeartbeatPayload(timestamp: now, version: "1.0"))
        let data = try message.encodeLengthPrefixed()
        let jsonData = data.subdata(in: 4..<data.count)
        let decoded = try CompanionMessage.decode(from: jsonData)

        if case .heartbeat(let payload) = decoded {
            #expect(payload.version == "1.0")
        } else {
            #expect(Bool(false), "Expected heartbeat message")
        }
    }

    @Test("CompanionMessage.error round-trips correctly")
    func errorMessageRoundTrips() throws {
        let message = CompanionMessage.error(ErrorPayload(code: "ERR_TEST", message: "something broke"))
        let data = try message.encodeLengthPrefixed()
        let jsonData = data.subdata(in: 4..<data.count)
        let decoded = try CompanionMessage.decode(from: jsonData)

        if case .error(let payload) = decoded {
            #expect(payload.message == "something broke")
            #expect(payload.code == "ERR_TEST")
        } else {
            #expect(Bool(false), "Expected error message")
        }
    }

    // MARK: - processIncomingDataForTesting

    @Test("processIncomingDataForTesting handles single statusUpdate frame")
    func processIncomingSingleFrame() throws {
        let service = MacConnectionService.shared
        service.disconnect()

        let message = CompanionMessage.statusUpdate(StatusUpdatePayload(
            isMonitoring: false,
            onlineTargets: 10,
            offlineTargets: 3,
            averageLatency: 25.0
        ))
        let data = try message.encodeLengthPrefixed()
        service.processIncomingDataForTesting(data)

        #expect(service.lastStatusUpdate?.onlineTargets == 10)
        #expect(service.lastStatusUpdate?.offlineTargets == 3)
        #expect(service.lastStatusUpdate?.averageLatency == 25.0)
    }

    @Test("processIncomingDataForTesting ignores incomplete frames")
    func processIncomingIncompleteFrame() {
        let service = MacConnectionService.shared
        service.disconnect()

        // Send only 2 bytes (less than the 4-byte length prefix)
        service.processIncomingDataForTesting(Data([0x00, 0x00]))
        #expect(service.lastStatusUpdate == nil)
    }

    @Test("processIncomingDataForTesting rejects absurdly large frame length")
    func processIncomingAbsurdFrameLength() {
        let service = MacConnectionService.shared
        service.disconnect()

        // Frame length of 0xFF_FF_FF_FF (>10MB limit)
        var data = Data([0xFF, 0xFF, 0xFF, 0xFF])
        data.append(Data(repeating: 0x00, count: 100))
        service.processIncomingDataForTesting(data)

        #expect(service.lastStatusUpdate == nil)
    }

    @Test("processIncomingDataForTesting handles deviceList message")
    func processIncomingDeviceList() throws {
        let service = MacConnectionService.shared
        service.disconnect()

        let device = DeviceInfo(
            ipAddress: "192.168.1.100",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "test-host",
            vendor: "Apple",
            deviceType: "computer",
            isOnline: true
        )
        let payload = DeviceListPayload(devices: [device])
        let message = CompanionMessage.deviceList(payload)
        let data = try message.encodeLengthPrefixed()

        service.processIncomingDataForTesting(data)

        #expect(service.lastDeviceList?.devices.count == 1)
        #expect(service.lastDeviceList?.devices.first?.ipAddress == "192.168.1.100")
        #expect(service.lastDeviceList?.devices.first?.hostname == "test-host")
    }
}
