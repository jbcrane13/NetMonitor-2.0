import Testing
@testable import NetMonitorCore

/// #388: every port a device-type rule reads must be in the quick fingerprint scan list.
@Suite("DeviceTypeInferenceService rule ports")
struct DeviceTypeRulePortsTests {

    @Test("Every rule port is in the fingerprint scan list")
    func everyRulePortIsScanned() {
        let scanned = Set(DeviceTypeInferenceService.fingerprintPorts)
        let missing = DeviceTypeInferenceService.rulePorts.subtracting(scanned)
        #expect(missing.isEmpty, "Rule ports not scanned: \(missing.sorted())")
    }

    @Test("The fingerprint list keeps the original ports and has no duplicates")
    func fingerprintListKeepsOriginalPorts() {
        let original: Set = [22, 53, 80, 443, 445, 548, 631, 3389, 5900, 8080, 8443, 8008, 9100, 32400, 62078]
        let ports = DeviceTypeInferenceService.fingerprintPorts
        #expect(original.isSubset(of: Set(ports)))
        #expect(Set(ports).count == ports.count)
    }

    /// Probes every TCP port against the port rules, alone and alongside each pair of the
    /// router trio, so a rule added with a literal port outside `rulePorts` fails here.
    @Test("Port rules react only to ports listed in rulePorts")
    func portRulesOnlyReadRulePorts() {
        let bases: [Set<Int>] = [[], [80, 443], [80, 53], [443, 53]]
        var reactive = Set<Int>()
        for base in bases {
            let baseline = DeviceTypeInferenceService.inferFromPorts(base)
            for port in 1...65535 where !base.contains(port) {
                if DeviceTypeInferenceService.inferFromPorts(base.union([port])) != baseline {
                    reactive.insert(port)
                }
            }
        }
        #expect(reactive.isSubset(of: DeviceTypeInferenceService.rulePorts),
                "Unlisted rule ports: \(reactive.subtracting(DeviceTypeInferenceService.rulePorts).sorted())")
    }

    @Test("Vendor rules that read ports use listed ports", arguments: [
        ("Samsung Electronics", 8001, DeviceType.tv),
        ("Samsung Electronics", 8002, DeviceType.tv),
        ("Microsoft Corporation", 3074, DeviceType.gaming)
    ])
    func vendorPortRules(vendor: String, port: Int, expected: DeviceType) {
        let device = LocalDevice(ipAddress: "192.168.1.100", macAddress: "00:00:F0:11:22:33", vendor: vendor, openPorts: [port])
        #expect(DeviceTypeInferenceService().inferDeviceType(for: device) == expected)
        #expect(DeviceTypeInferenceService.rulePorts.contains(port))
        #expect(DeviceTypeInferenceService.fingerprintPorts.contains(port))
    }
}
