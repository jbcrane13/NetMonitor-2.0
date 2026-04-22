import Testing
import Foundation
@testable import NetworkScanKit

@Suite("SSDPScanPhase")
struct SSDPScanPhaseTests {

    // MARK: - Phase metadata

    @Test("id is 'ssdp'")
    func phaseIDIsSsdp() {
        let phase = SSDPScanPhase()
        #expect(phase.id == "ssdp")
    }

    @Test("displayName is 'UPnP discovery…'")
    func phaseDisplayName() {
        let phase = SSDPScanPhase()
        #expect(phase.displayName == "UPnP discovery…")
    }

    @Test("weight is 0.06")
    func phaseWeightValue() {
        let phase = SSDPScanPhase()
        #expect(phase.weight == 0.06)
    }

    @Test("weight is positive")
    func phaseWeightIsPositive() {
        let phase = SSDPScanPhase()
        #expect(phase.weight > 0)
    }

    @Test("conforms to ScanPhase protocol")
    func phaseConformsToScanPhase() {
        let phase: any ScanPhase = SSDPScanPhase()
        #expect(phase.id == "ssdp")
        #expect(phase.displayName == "UPnP discovery…")
        #expect(phase.weight == 0.06)
    }

    // MARK: - extractIPFromSSDPResponse (IPv4Helpers.swift)

    @Test("LOCATION header with standard URL extracts IP")
    func extractIPFromLocationHeader() {
        let response = """
        HTTP/1.1 200 OK\r\n
        LOCATION: http://192.168.1.1:1900/description.xml\r\n
        ST: ssdp:all\r\n
        \r\n

        """
        let ip = extractIPFromSSDPResponse(response)
        #expect(ip == "192.168.1.1")
    }

    @Test("LOCATION header with different IP extracts correct IP")
    func extractIPFromLocationHeaderAlternateIP() {
        let response = "LOCATION: http://10.0.0.50:49152/rootDesc.xml\r\n"
        let ip = extractIPFromSSDPResponse(response)
        #expect(ip == "10.0.0.50")
    }

    @Test("extractIPFromSSDPResponse with no IP returns nil")
    func extractIPFromResponseWithNoIP() {
        let response = "HTTP/1.1 200 OK\r\nST: ssdp:all\r\n"
        let ip = extractIPFromSSDPResponse(response)
        #expect(ip == nil)
    }

    @Test("extractIPFromSSDPResponse with empty string returns nil")
    func extractIPFromEmptyString() {
        let ip = extractIPFromSSDPResponse("")
        #expect(ip == nil)
    }

    @Test("extractIPFromSSDPResponse extracts from embedded LOCATION line")
    func extractIPFromEmbeddedLocation() {
        let response = """
        HTTP/1.1 200 OK\r\n
        Cache-Control: max-age=1800\r\n
        LOCATION: http://192.168.0.100:80/upnp/control\r\n
        Server: UPnP/1.0\r\n
        """
        let ip = extractIPFromSSDPResponse(response)
        #expect(ip == "192.168.0.100")
    }

    @Test("LOCATION header is case-insensitive")
    func extractIPIsCaseInsensitive() {
        let response = "location: http://172.16.0.1:8080/desc.xml\r\n"
        let ip = extractIPFromSSDPResponse(response)
        #expect(ip == "172.16.0.1")
    }

    @Test("extractIPFromSSDPResponse with multiple IPs returns first from LOCATION")
    func extractIPWithMultipleIPs() {
        let response = """
        HTTP/1.1 200 OK\r\n
        LOCATION: http://192.168.1.1:1900/desc.xml\r\n
        USN: uuid:device-10.0.0.1::upnp:rootdevice\r\n
        """
        let ip = extractIPFromSSDPResponse(response)
        #expect(ip == "192.168.1.1")
    }

    // MARK: - Execute with subnet filter

    @Test("execute with reject-all subnet filter completes without crash")
    func executeWithSubnetFilterCompletes() async {
        let phase = SSDPScanPhase()
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in false },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = SSDPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // No devices should be added when filter rejects all
        #expect(await accumulator.isEmpty)

        // Progress must start at 0 and end at 1
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    @Test("execute with accept-all subnet filter completes without crash")
    func executeWithAcceptAllSubnetFilterCompletes() async {
        let phase = SSDPScanPhase()
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = SSDPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    @Test("execute reports at least 3 progress values")
    func executeReportsMultipleProgressValues() async {
        let phase = SSDPScanPhase()
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in false },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = SSDPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        let values = await collector.values
        // 0.0, 0.7, 1.0 at minimum
        #expect(values.count >= 3)
    }

    @Test("devices from SSDP have source .ssdp when accepted by filter")
    func devicesFromSSDPHaveCorrectSource() async {
        let phase = SSDPScanPhase()
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        // If any devices are found, they should have source .ssdp
        let devices = await accumulator.snapshot()
        for device in devices {
            #expect(device.source == .ssdp)
        }
    }

    @Test("devices from SSDP have nil hostname and nil macAddress")
    func devicesFromSSDPHaveNilOptionalFields() async {
        let phase = SSDPScanPhase()
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        let devices = await accumulator.snapshot()
        for device in devices {
            #expect(device.hostname == nil)
            #expect(device.macAddress == nil)
            #expect(device.vendor == nil)
        }
    }

    // MARK: - isValidIPv4Address (used in SSDP response parsing)

    @Test("isValidIPv4Address validates correct addresses")
    func validIPv4Addresses() {
        #expect(isValidIPv4Address("192.168.1.1"))
        #expect(isValidIPv4Address("10.0.0.1"))
        #expect(isValidIPv4Address("0.0.0.0"))
        #expect(isValidIPv4Address("255.255.255.255"))
    }

    @Test("isValidIPv4Address rejects invalid addresses")
    func invalidIPv4Addresses() {
        #expect(!isValidIPv4Address(""))
        #expect(!isValidIPv4Address("192.168.1"))
        #expect(!isValidIPv4Address("192.168.1.1.1"))
        #expect(!isValidIPv4Address("999.999.999.999"))
        #expect(!isValidIPv4Address("not.an.ip.address"))
    }

    // MARK: - firstIPv4Address

    @Test("firstIPv4Address extracts IP from URL")
    func firstIPv4AddressFromURL() {
        let ip = firstIPv4Address(in: "http://192.168.1.50:8080/path")
        #expect(ip == "192.168.1.50")
    }

    @Test("firstIPv4Address returns nil when no IP present")
    func firstIPv4AddressNoIP() {
        let ip = firstIPv4Address(in: "no ip here")
        #expect(ip == nil)
    }

    // MARK: - cleanedIPv4Address

    @Test("cleanedIPv4Address strips zone ID suffix")
    func cleanedIPv4AddressStripsZoneID() {
        let result = cleanedIPv4Address("192.168.1.1%en0")
        #expect(result == "192.168.1.1")
    }

    @Test("cleanedIPv4Address returns nil for invalid IPv4")
    func cleanedIPv4AddressReturnsNilForInvalid() {
        let result = cleanedIPv4Address("not-an-ip%en0")
        #expect(result == nil)
    }

    @Test("cleanedIPv4Address returns clean address without zone ID")
    func cleanedIPv4AddressWithoutZoneID() {
        let result = cleanedIPv4Address("10.0.0.1")
        #expect(result == "10.0.0.1")
    }
}

// MARK: - Actor helper for Sendable closure collection

private actor SSDPProgressCollector {
    private var _values: [Double] = []
    func append(_ v: Double) { _values.append(v) }
    var values: [Double] { _values }
}
