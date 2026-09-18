import Testing
import NetworkScanKit
@testable import NetMonitorCore

/// Tests for `ScanDisplayPhase(phaseID:)`, the mapping used by `DeviceDiscoveryService`
/// to translate a NetworkScanKit `ScanPhaseID` into the UI-facing display phase.
struct DeviceDiscoveryServiceTests {

    // MARK: - ScanDisplayPhase(phaseID:)

    @Test("every built-in ScanPhaseID maps to a non-nil ScanDisplayPhase")
    func everyBuiltInScanPhaseIDMapsToNonNilScanDisplayPhase() {
        let builtInPhaseIDs: [ScanPhaseID] = [.arp, .bonjour, .tcpProbe, .ssdp, .icmpLatency, .reverseDNS]
        for phaseID in builtInPhaseIDs {
            #expect(ScanDisplayPhase(phaseID: phaseID) != nil, "\(phaseID.rawValue) should map to a display phase")
        }
    }

    @Test("an unknown ScanPhaseID maps to a nil ScanDisplayPhase")
    func unknownScanPhaseIDMapsToNilScanDisplayPhase() {
        #expect(ScanDisplayPhase(phaseID: "custom-platform-phase") == nil)
    }
}
