import Foundation
import Testing
@testable import NetworkScanKit

/// "Online only if it answered this scan" (#378): which reports count as evidence,
/// how snapshots carry `isCached`, the ARP re-check phase, and old-cache decoding.
struct ScanPresenceTests {

    private static func device(_ ip: String, hostname: String? = nil, source: DeviceSource = .local) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip, hostname: hostname, vendor: nil, macAddress: nil,
            latency: nil, discoveredAt: Date(), source: source
        )
    }

    private static func context() -> ScanContext {
        ScanContext(hosts: [], subnetFilter: { _ in true }, localIP: nil)
    }

    // MARK: - Accumulator

    @Test("a device reported without evidence is cached")
    func unconfirmedIsCached() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(Self.device("10.0.0.2"), confirmsPresence: false)
        #expect(await accumulator.snapshot().first?.isCached == true)
    }

    @Test("upserts default to evidence, so existing callers stay online")
    func defaultUpsertConfirms() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(Self.device("10.0.0.2"))
        #expect(await accumulator.snapshot().first?.isCached == false)
    }

    @Test("a later answer confirms a cached device")
    func laterAnswerConfirms() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(Self.device("10.0.0.2"), confirmsPresence: false)
        await accumulator.upsert(Self.device("10.0.0.2", source: .bonjour))
        #expect(await accumulator.sortedSnapshot().first?.isCached == false)
    }

    @Test("a measured latency confirms a cached device")
    func latencyConfirms() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(Self.device("10.0.0.2"), confirmsPresence: false)
        await accumulator.setLatency(ip: "10.0.0.2", value: 3, source: .icmp)
        #expect(await accumulator.snapshot().first?.isCached == false)
    }

    @Test("enrichment never confirms, and never un-confirms")
    func enrichmentIsNeutral() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(Self.device("10.0.0.2"), confirmsPresence: false)
        await accumulator.upsert(Self.device("10.0.0.3"))
        await accumulator.upsert(Self.device("10.0.0.2", hostname: "printer"), confirmsPresence: false)
        await accumulator.upsert(Self.device("10.0.0.3", hostname: "nas"), confirmsPresence: false)

        let byIP = await Dictionary(uniqueKeysWithValues: accumulator.snapshot().map { ($0.ipAddress, $0) })
        #expect(byIP["10.0.0.2"]?.isCached == true)
        #expect(byIP["10.0.0.2"]?.hostname == "printer")
        #expect(byIP["10.0.0.3"]?.isCached == false)
    }

    @Test("reset clears presence state and the ARP baseline")
    func resetClearsPresence() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(Self.device("10.0.0.2"), confirmsPresence: false)
        await accumulator.recordARPBaseline(["10.0.0.2": 5])
        await accumulator.reset()
        #expect(await accumulator.unconfirmedDeviceIPs().isEmpty)
        #expect(await accumulator.arpBaselineExpiries().isEmpty)
    }

    // MARK: - ARPRecheckPhase

    @Test("re-check confirms devices whose ARP entry moved forward, and only those")
    func recheckConfirmsRefreshed() async {
        let accumulator = ScanAccumulator()
        await accumulator.recordARPBaseline(["10.0.0.2": 1, "10.0.0.3": 1])
        await accumulator.upsert(Self.device("10.0.0.2"), confirmsPresence: false)
        await accumulator.upsert(Self.device("10.0.0.3"), confirmsPresence: false)

        let phase = ARPRecheckPhase(readEntries: {
            [
                ARPEntry(ip: "10.0.0.2", mac: "aa:bb:cc:dd:ee:02", expiry: 1_200), // pinged, re-ARPed
                ARPEntry(ip: "10.0.0.3", mac: "aa:bb:cc:dd:ee:03", expiry: 1) // still stale
            ]
        })
        await phase.execute(context: Self.context(), accumulator: accumulator) { _ in }

        #expect(await accumulator.unconfirmedDeviceIPs() == ["10.0.0.3"])
    }

    @Test("re-check with an empty ARP table leaves everything as it was")
    func recheckWithEmptyTable() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(Self.device("10.0.0.2"), confirmsPresence: false)
        let phase = ARPRecheckPhase(readEntries: { [] })
        await phase.execute(context: Self.context(), accumulator: accumulator) { _ in }
        #expect(await accumulator.unconfirmedDeviceIPs() == ["10.0.0.2"])
    }

    // MARK: - DiscoveredDevice

    @Test("JSON caches written before isCached existed decode as not cached")
    func decodesOldCache() throws {
        let old = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","ipAddress":"10.0.0.2","discoveredAt":0,"source":"local"}
        """
        let device = try JSONDecoder().decode(DiscoveredDevice.self, from: Data(old.utf8))
        #expect(device.isCached == false)
        #expect(device.ipAddress == "10.0.0.2")
    }

    @Test("isCached survives an encode/decode round trip")
    func roundTripsCached() throws {
        let cached = Self.device("10.0.0.2").withCached(true)
        let decoded = try JSONDecoder().decode(DiscoveredDevice.self, from: JSONEncoder().encode(cached))
        #expect(decoded.isCached == true)
        #expect(decoded.id == cached.id)
    }

    @Test("a cached device with no latency says Cached")
    func cachedLatencyText() {
        #expect(Self.device("10.0.0.2").withCached(true).latencyText == "Cached")
        #expect(Self.device("10.0.0.2").latencyText == "—")
    }
}
