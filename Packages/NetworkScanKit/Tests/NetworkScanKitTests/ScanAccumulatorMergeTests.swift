import Testing
import Foundation
@testable import NetworkScanKit

// MARK: - ScanAccumulator Device Merging (NetMonitor20-rft)
//
// NOTE: ScanAccumulator keys by IP address only — there is no MAC-based merging
// path in the implementation. Tests here verify the actual merge semantics:
// same-IP upserts merge fields (existing wins), and different IPs are stored
// independently regardless of MAC address.

struct ScanAccumulatorMergeTests {

    private func makeDevice(
        ip: String,
        mac: String? = nil,
        hostname: String? = nil,
        vendor: String? = nil,
        latency: Double? = nil,
        source: DeviceSource = .local
    ) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip,
            hostname: hostname,
            vendor: vendor,
            macAddress: mac,
            latency: latency,
            discoveredAt: Date(),
            source: source
        )
    }

    // MARK: - Same IP, Different Sources → Merge

    @Test("Same IP from ARP then Bonjour merges into one device entry")
    func sameIPDifferentSourcesMergedToOne() async {
        let acc = ScanAccumulator()
        let arpDevice = makeDevice(ip: "192.168.1.50", mac: "AA:BB:CC:DD:EE:01",
                                   hostname: nil, source: .local)
        let bonjourDevice = makeDevice(ip: "192.168.1.50", mac: "AA:BB:CC:DD:EE:01",
                                       hostname: "living-room-appletv.local", source: .bonjour)
        await acc.upsert(arpDevice)
        await acc.upsert(bonjourDevice)

        let devices = await acc.snapshot()
        #expect(devices.count == 1, "Two upserts with the same IP should yield exactly one device")
    }

    @Test("Merged device retains hostname from second upsert when first had nil hostname")
    func mergedDeviceBackfillsHostnameFromIncoming() async {
        let acc = ScanAccumulator()
        let first = makeDevice(ip: "192.168.1.50", hostname: nil, vendor: nil)
        let second = makeDevice(ip: "192.168.1.50", hostname: "smart-speaker.local", vendor: "Sonos")
        await acc.upsert(first)
        await acc.upsert(second)

        let devices = await acc.snapshot()
        #expect(devices.count == 1)
        #expect(devices[0].hostname == "smart-speaker.local",
                "Hostname should be filled from the second upsert when the first had nil")
        #expect(devices[0].vendor == "Sonos",
                "Vendor should be filled from the second upsert when the first had nil")
    }

    @Test("Merged device preserves existing hostname when second upsert conflicts")
    func mergedDeviceKeepsExistingHostnameOnConflict() async {
        let acc = ScanAccumulator()
        let first = makeDevice(ip: "192.168.1.50", hostname: "original.local")
        let second = makeDevice(ip: "192.168.1.50", hostname: "interloper.local")
        await acc.upsert(first)
        await acc.upsert(second)

        let devices = await acc.snapshot()
        #expect(devices[0].hostname == "original.local",
                "Existing hostname wins over incoming hostname on merge conflict")
    }

    @Test("Merged device MAC address: existing wins over incoming")
    func mergedDeviceMACExistingWins() async {
        let acc = ScanAccumulator()
        let first = makeDevice(ip: "192.168.1.50", mac: "AA:BB:CC:DD:EE:FF")
        let second = makeDevice(ip: "192.168.1.50", mac: "11:22:33:44:55:66")
        await acc.upsert(first)
        await acc.upsert(second)

        let devices = await acc.snapshot()
        #expect(devices[0].macAddress == "AA:BB:CC:DD:EE:FF",
                "Existing MAC address should be preserved on merge conflict")
    }

    @Test("Merged device MAC backfilled when existing had no MAC")
    func mergedDeviceMACBackfilledFromIncoming() async {
        let acc = ScanAccumulator()
        let first = makeDevice(ip: "192.168.1.50", mac: nil)
        let second = makeDevice(ip: "192.168.1.50", mac: "AA:BB:CC:00:11:22")
        await acc.upsert(first)
        await acc.upsert(second)

        let devices = await acc.snapshot()
        #expect(devices[0].macAddress == "AA:BB:CC:00:11:22",
                "MAC should be backfilled from incoming when existing had nil")
    }

    // MARK: - Same MAC, Different IP → Two Distinct Entries (DHCP reassignment)

    @Test("Same MAC address at different IPs creates two independent device entries")
    func sameMACDifferentIPStoresAsDistinct() async {
        // The accumulator indexes by IP, not MAC — two IPs are always two entries
        let acc = ScanAccumulator()
        let deviceA = makeDevice(ip: "192.168.1.10", mac: "AA:BB:CC:DD:EE:FF")
        let deviceB = makeDevice(ip: "192.168.1.11", mac: "AA:BB:CC:DD:EE:FF")
        await acc.upsert(deviceA)
        await acc.upsert(deviceB)

        #expect(await acc.count == 2,
                "Devices with the same MAC but different IPs should be stored as two entries " +
                "(accumulator keys by IP, not MAC)")
        #expect(await acc.contains(ip: "192.168.1.10"))
        #expect(await acc.contains(ip: "192.168.1.11"))
    }

    // MARK: - networkProfileID Merge

    @Test("networkProfileID backfilled from incoming when existing had nil")
    func networkProfileIDBackfilledFromIncoming() async {
        let acc = ScanAccumulator()
        let profileID = UUID()
        let first = makeDevice(ip: "192.168.1.50")
        let second = DiscoveredDevice(
            ipAddress: "192.168.1.50",
            hostname: nil,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local,
            networkProfileID: profileID
        )
        await acc.upsert(first)
        await acc.upsert(second)

        let devices = await acc.snapshot()
        #expect(devices[0].networkProfileID == profileID,
                "networkProfileID should be backfilled from incoming when existing had nil")
    }

    @Test("networkProfileID of existing is preserved when both have a value")
    func networkProfileIDExistingPreserved() async {
        let acc = ScanAccumulator()
        let firstID = UUID()
        let secondID = UUID()
        let first = DiscoveredDevice(
            ipAddress: "192.168.1.50",
            hostname: nil,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local,
            networkProfileID: firstID
        )
        let second = DiscoveredDevice(
            ipAddress: "192.168.1.50",
            hostname: nil,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local,
            networkProfileID: secondID
        )
        await acc.upsert(first)
        await acc.upsert(second)

        let devices = await acc.snapshot()
        #expect(devices[0].networkProfileID == firstID,
                "Existing networkProfileID should win when both entries have one")
    }

    // MARK: - Source Preservation

    @Test("Source from the first upsert is preserved on subsequent merges")
    func sourceOfFirstUpsertIsPreserved() async {
        let acc = ScanAccumulator()
        let first = makeDevice(ip: "192.168.1.50", source: .local)
        let second = makeDevice(ip: "192.168.1.50", source: .bonjour)
        await acc.upsert(first)
        await acc.upsert(second)

        let devices = await acc.snapshot()
        #expect(devices[0].source == .local,
                "The source field from the first upsert should be preserved on merge")
    }

    // MARK: - discoveredAt Preservation

    @Test("discoveredAt from the first upsert is preserved on subsequent merges")
    func discoveredAtOfFirstUpsertIsPreserved() async {
        let acc = ScanAccumulator()
        let earlyDate = Date(timeIntervalSinceNow: -60)
        let lateDate = Date()

        let first = DiscoveredDevice(
            ipAddress: "192.168.1.50",
            hostname: nil,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: earlyDate,
            source: .local
        )
        let second = DiscoveredDevice(
            ipAddress: "192.168.1.50",
            hostname: "updated.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: lateDate,
            source: .local
        )
        await acc.upsert(first)
        await acc.upsert(second)

        let devices = await acc.snapshot()
        #expect(devices[0].discoveredAt == earlyDate,
                "discoveredAt should be the original discovery time, not updated on merge")
    }
}
