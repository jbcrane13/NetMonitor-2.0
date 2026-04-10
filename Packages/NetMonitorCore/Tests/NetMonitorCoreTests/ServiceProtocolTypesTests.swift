import Testing
import Foundation
@testable import NetMonitorCore

struct ServiceProtocolTypesTests {

    // MARK: - WakeOnLANResult

    @Test("WakeOnLANResult init stores properties correctly")
    func wakeOnLANResultInit() {
        let result = WakeOnLANResult(macAddress: "AA:BB:CC:DD:EE:FF", success: true)
        #expect(result.macAddress == "AA:BB:CC:DD:EE:FF")
        #expect(result.success == true)
        #expect(result.error == nil)
    }

    @Test("WakeOnLANResult stores error message when provided")
    func wakeOnLANResultWithError() {
        let result = WakeOnLANResult(macAddress: "00:11:22:33:44:55", success: false, error: "Network unreachable")
        #expect(result.macAddress == "00:11:22:33:44:55")
        #expect(result.success == false)
        #expect(result.error == "Network unreachable")
    }

    @Test("WakeOnLANResult sentAt is set near creation time")
    func wakeOnLANResultSentAt() {
        let before = Date()
        let result = WakeOnLANResult(macAddress: "AA:BB:CC:DD:EE:FF", success: true)
        let after = Date()
        #expect(result.sentAt >= before)
        #expect(result.sentAt <= after)
    }

    // MARK: - SpeedTestData

    @Test("SpeedTestData init stores required properties")
    func speedTestDataInit() {
        let data = SpeedTestData(downloadSpeed: 100.0, uploadSpeed: 50.0, latency: 10.0)
        #expect(data.downloadSpeed == 100.0)
        #expect(data.uploadSpeed == 50.0)
        #expect(data.latency == 10.0)
        #expect(data.jitter == nil)
        #expect(data.serverName == nil)
    }

    @Test("SpeedTestData stores optional jitter and serverName")
    func speedTestDataWithOptionals() {
        let data = SpeedTestData(
            downloadSpeed: 500.0,
            uploadSpeed: 100.0,
            latency: 5.5,
            jitter: 1.2,
            serverName: "Test Server"
        )
        #expect(data.jitter == 1.2)
        #expect(data.serverName == "Test Server")
    }

    // MARK: - SpeedTestPhase

    @Test("SpeedTestPhase has all expected cases with correct rawValues")
    func speedTestPhaseRawValues() {
        #expect(SpeedTestPhase.idle.rawValue == "idle")
        #expect(SpeedTestPhase.latency.rawValue == "latency")
        #expect(SpeedTestPhase.download.rawValue == "download")
        #expect(SpeedTestPhase.upload.rawValue == "upload")
        #expect(SpeedTestPhase.complete.rawValue == "complete")
    }

    @Test("SpeedTestPhase roundtrips through rawValue")
    func speedTestPhaseRoundtrip() {
        #expect(SpeedTestPhase(rawValue: "idle") == .idle)
        #expect(SpeedTestPhase(rawValue: "complete") == .complete)
        #expect(SpeedTestPhase(rawValue: "unknown") == nil)
    }

    // MARK: - ScanDisplayPhase

    @Test("ScanDisplayPhase rawValues match expected display strings")
    func scanDisplayPhaseRawValues() {
        #expect(ScanDisplayPhase.idle.rawValue == "")
        #expect(ScanDisplayPhase.arpScan.rawValue == "Scanning network\u{2026}")
        #expect(ScanDisplayPhase.tcpProbe.rawValue == "Probing ports\u{2026}")
        #expect(ScanDisplayPhase.bonjour.rawValue == "Bonjour discovery\u{2026}")
        #expect(ScanDisplayPhase.ssdp.rawValue == "UPnP discovery\u{2026}")
        #expect(ScanDisplayPhase.icmpLatency.rawValue == "Measuring latency\u{2026}")
        #expect(ScanDisplayPhase.companion.rawValue == "Mac companion\u{2026}")
        #expect(ScanDisplayPhase.resolving.rawValue == "Resolving names\u{2026}")
        #expect(ScanDisplayPhase.done.rawValue == "Complete")
    }

    // MARK: - MacConnectionState

    @Test("MacConnectionState.isConnected is true only for .connected")
    func macConnectionStateIsConnected() {
        #expect(MacConnectionState.connected.isConnected == true)
        #expect(MacConnectionState.disconnected.isConnected == false)
        #expect(MacConnectionState.browsing.isConnected == false)
        #expect(MacConnectionState.connecting.isConnected == false)
        #expect(MacConnectionState.error("test error").isConnected == false)
    }

    @Test("MacConnectionState Equatable: equal cases match")
    func macConnectionStateEqualitySame() {
        #expect(MacConnectionState.connected == MacConnectionState.connected)
        #expect(MacConnectionState.disconnected == MacConnectionState.disconnected)
        #expect(MacConnectionState.browsing == MacConnectionState.browsing)
        #expect(MacConnectionState.connecting == MacConnectionState.connecting)
        #expect(MacConnectionState.error("same") == MacConnectionState.error("same"))
    }

    @Test("MacConnectionState Equatable: different cases don't match")
    func macConnectionStateEqualityDifferent() {
        #expect(MacConnectionState.connected != MacConnectionState.disconnected)
        #expect(MacConnectionState.error("a") != MacConnectionState.error("b"))
        #expect(MacConnectionState.connected != MacConnectionState.error("connected"))
    }

    // MARK: - DiscoveredMac

    @Test("DiscoveredMac init stores id and name")
    func discoveredMacInit() {
        let mac = DiscoveredMac(id: "device-1", name: "My Mac Pro")
        #expect(mac.id == "device-1")
        #expect(mac.name == "My Mac Pro")
    }

    @Test("DiscoveredMac Equatable: same id and name are equal")
    func discoveredMacEqualitySame() {
        let mac1 = DiscoveredMac(id: "device-1", name: "My Mac")
        let mac2 = DiscoveredMac(id: "device-1", name: "My Mac")
        #expect(mac1 == mac2)
    }

    @Test("DiscoveredMac Equatable: different id produces inequality")
    func discoveredMacEqualityDifferentId() {
        let mac1 = DiscoveredMac(id: "device-1", name: "My Mac")
        let mac2 = DiscoveredMac(id: "device-2", name: "My Mac")
        #expect(mac1 != mac2)
    }

    @Test("DiscoveredMac Equatable: different name produces inequality")
    func discoveredMacEqualityDifferentName() {
        let mac1 = DiscoveredMac(id: "device-1", name: "Mac A")
        let mac2 = DiscoveredMac(id: "device-1", name: "Mac B")
        #expect(mac1 != mac2)
    }
}
