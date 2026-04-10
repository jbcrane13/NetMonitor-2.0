import Testing
@testable import NetworkScanKit

/// Tests for SSDPScanPhase metadata and extractIPFromSSDPResponse parsing.
/// The actual M-SEARCH multicast (NWConnection over Wi-Fi) is excluded — it
/// requires a live network interface and is non-deterministic in a test host.
struct SSDPScanPhaseTests {

    // MARK: - Phase metadata

    @Test("SSDPScanPhase id is 'ssdp'")
    func phaseIDIsSsdp() {
        let phase = SSDPScanPhase()
        #expect(phase.id == "ssdp")
    }

    @Test("SSDPScanPhase displayName is 'UPnP discovery…'")
    func phaseDisplayName() {
        let phase = SSDPScanPhase()
        #expect(phase.displayName == "UPnP discovery…")
    }

    @Test("SSDPScanPhase weight is positive")
    func phaseWeightIsPositive() {
        let phase = SSDPScanPhase()
        #expect(phase.weight > 0)
    }

    @Test("SSDPScanPhase weight is 0.06")
    func phaseWeightValue() {
        let phase = SSDPScanPhase()
        #expect(phase.weight == 0.06)
    }

    @Test("SSDPScanPhase conforms to ScanPhase protocol")
    func phaseConformsToScanPhase() {
        let phase: any ScanPhase = SSDPScanPhase()
        #expect(phase.id == "ssdp")
    }

    // MARK: - extractIPFromSSDPResponse (IPv4Helpers.swift)

    @Test("LOCATION header with standard URL extracts IP")
    func extractIPFromLocationHeader() {
        let response = """
        HTTP/1.1 200 OK\r
        LOCATION: http://192.168.1.1:1900/description.xml\r
        ST: ssdp:all\r
        \r

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
        HTTP/1.1 200 OK\r
        Cache-Control: max-age=1800\r
        LOCATION: http://192.168.0.100:80/upnp/control\r
        Server: UPnP/1.0\r
        """
        let ip = extractIPFromSSDPResponse(response)
        #expect(ip == "192.168.0.100")
    }

    // MARK: - SSDPScanPhase executes without crashing on no-network context

    @Test("execute with subnet filter completes without crash")
    func executeWithSubnetFilterCompletes() async {
        let phase = SSDPScanPhase()
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in false },  // reject all IPs — no devices added
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = SSDPProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // Progress must start at 0 and end at 1
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }
}

// MARK: - Actor helper for Sendable closure collection

private actor SSDPProgressCollector {
    private var _values: [Double] = []
    func append(_ v: Double) { _values.append(v) }
    var values: [Double] { _values }
}
