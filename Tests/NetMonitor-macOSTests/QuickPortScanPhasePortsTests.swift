import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

/// #388: the Mac quick port scan must probe every port the device-type rules read.
@Suite("QuickPortScanPhase ports")
struct QuickPortScanPhasePortsTests {

    @Test("Every device-type rule port is scanned")
    func everyRulePortIsScanned() {
        let missing = DeviceTypeInferenceService.rulePorts.subtracting(QuickPortScanPhase.commonPorts)
        #expect(missing.isEmpty, "Rule ports the Mac never scans: \(missing.sorted())")
    }

    @Test("Samsung TV, Chromecast and Xbox ports are scanned", arguments: [8001, 8002, 8009, 3074])
    func reviewPortsAreScanned(port: Int) {
        #expect(QuickPortScanPhase.commonPorts.contains(port))
    }

    @Test("Every security-readout rule port is scanned (#454)")
    func everySecurityRulePortIsScanned() {
        let missing = SecurityRuleTable.ports.subtracting(QuickPortScanPhase.commonPorts)
        #expect(missing.isEmpty, "Security rule ports the Mac never scans: \(missing.sorted())")
        #expect(QuickPortScanPhase.commonPorts.count == Set(QuickPortScanPhase.commonPorts).count)
    }
}
