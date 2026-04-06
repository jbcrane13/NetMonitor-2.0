import Testing
import Foundation
@testable import NetworkScanKit

@Suite("ScanAccumulator")
struct ScanAccumulatorTests {

    private func makeDevice(
        ip: String,
        hostname: String? = nil,
        vendor: String? = nil,
        macAddress: String? = nil,
        latency: Double? = nil,
        source: DeviceSource = .local
    ) -> DiscoveredDevice {
        DiscoveredDevice(
            ipAddress: ip,
            hostname: hostname,
            vendor: vendor,
            macAddress: macAddress,
            latency: latency,
            discoveredAt: Date(),
            source: source
        )
    }

    @Test("starts empty")
    func startsEmpty() async {
        let acc = ScanAccumulator()
        #expect(await acc.isEmpty)
        #expect(await acc.snapshot().isEmpty)
    }

    @Test("upsert adds new device")
    func upsertAddsDevice() async {
        let acc = ScanAccumulator()
        let device = makeDevice(ip: "192.168.1.1")
        await acc.upsert(device)
        #expect(await acc.count == 1)
        #expect(await acc.contains(ip: "192.168.1.1"))
    }

    @Test("upsert multiple unique devices")
    func upsertMultipleUnique() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "192.168.1.1"))
        await acc.upsert(makeDevice(ip: "192.168.1.2"))
        await acc.upsert(makeDevice(ip: "192.168.1.3"))
        #expect(await acc.count == 3)
    }

    @Test("upsert with same IP merges - existing fields win")
    func upsertMergesExistingFieldsWin() async {
        let acc = ScanAccumulator()
        let first = makeDevice(ip: "192.168.1.1", hostname: "original.local", vendor: "VendorA", latency: 5.0)
        let second = makeDevice(ip: "192.168.1.1", hostname: "override.local", vendor: "VendorB", latency: 10.0)
        await acc.upsert(first)
        await acc.upsert(second)
        #expect(await acc.count == 1)
        let devices = await acc.snapshot()
        let merged = devices[0]
        // existing fields take priority
        #expect(merged.hostname == "original.local")
        #expect(merged.vendor == "VendorA")
        #expect(merged.latency == 5.0)
    }

    @Test("upsert fills in nil fields from incoming")
    func upsertFillsNilFromIncoming() async {
        let acc = ScanAccumulator()
        let first = makeDevice(ip: "192.168.1.1", hostname: nil, vendor: nil)
        let second = makeDevice(ip: "192.168.1.1", hostname: "filled.local", vendor: "Apple")
        await acc.upsert(first)
        await acc.upsert(second)
        let devices = await acc.snapshot()
        #expect(devices[0].hostname == "filled.local")
        #expect(devices[0].vendor == "Apple")
    }

    @Test("contains returns false for unknown IP")
    func containsReturnsFalse() async {
        let acc = ScanAccumulator()
        #expect(await acc.contains(ip: "10.0.0.99") == false)
    }

    @Test("contains returns true after insert")
    func containsReturnsTrueAfterInsert() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "10.0.0.1"))
        #expect(await acc.contains(ip: "10.0.0.1") == true)
    }

    @Test("knownIPs returns all inserted IPs")
    func knownIPsReturnsAll() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "192.168.1.1"))
        await acc.upsert(makeDevice(ip: "192.168.1.2"))
        let ips = await acc.knownIPs()
        #expect(ips == Set(["192.168.1.1", "192.168.1.2"]))
    }

    @Test("ipsWithoutLatency returns IPs missing latency")
    func ipsWithoutLatency() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "192.168.1.1", latency: 5.0))  // has latency
        await acc.upsert(makeDevice(ip: "192.168.1.2", latency: nil))   // no latency
        await acc.upsert(makeDevice(ip: "192.168.1.3", latency: nil))   // no latency
        let missing = await acc.ipsWithoutLatency()
        #expect(missing.count == 2)
        #expect(missing.contains("192.168.1.2"))
        #expect(missing.contains("192.168.1.3"))
    }

    @Test("allDeviceIPs returns all IPs")
    func allDeviceIPs() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "10.0.0.1"))
        await acc.upsert(makeDevice(ip: "10.0.0.2"))
        let all = await acc.allDeviceIPs()
        #expect(all.count == 2)
        #expect(all.contains("10.0.0.1"))
        #expect(all.contains("10.0.0.2"))
    }

    @Test("updateLatency sets latency when nil")
    func updateLatencySetsWhenNil() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "192.168.1.1", latency: nil))
        await acc.updateLatency(ip: "192.168.1.1", latency: 42.0)
        let devices = await acc.snapshot()
        #expect(devices[0].latency == 42.0)
    }

    @Test("updateLatency does not overwrite existing latency")
    func updateLatencyDoesNotOverwrite() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "192.168.1.1", latency: 10.0))
        await acc.updateLatency(ip: "192.168.1.1", latency: 99.0)
        let devices = await acc.snapshot()
        #expect(devices[0].latency == 10.0)
    }

    @Test("updateLatency is no-op for unknown IP")
    func updateLatencyUnknownIP() async {
        let acc = ScanAccumulator()
        await acc.updateLatency(ip: "10.0.0.99", latency: 5.0)  // should not crash
        #expect(await acc.isEmpty)
    }

    @Test("replaceLatency overwrites existing latency")
    func replaceLatencyOverwrites() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "192.168.1.1", latency: 10.0))
        await acc.replaceLatency(ip: "192.168.1.1", latency: 2.0)
        let devices = await acc.snapshot()
        #expect(devices[0].latency == 2.0)
    }

    @Test("replaceLatency is no-op for unknown IP")
    func replaceLatencyUnknownIP() async {
        let acc = ScanAccumulator()
        await acc.replaceLatency(ip: "10.0.0.99", latency: 5.0)  // should not crash
        #expect(await acc.isEmpty)
    }

    @Test("sortedSnapshot returns devices in numeric IP order")
    func sortedSnapshotNumericOrder() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "10.0.0.10"))
        await acc.upsert(makeDevice(ip: "10.0.0.9"))
        await acc.upsert(makeDevice(ip: "10.0.0.100"))
        let sorted = await acc.sortedSnapshot()
        #expect(sorted[0].ipAddress == "10.0.0.9")
        #expect(sorted[1].ipAddress == "10.0.0.10")
        #expect(sorted[2].ipAddress == "10.0.0.100")
    }

    @Test("reset clears all state")
    func resetClearsAll() async {
        let acc = ScanAccumulator()
        await acc.upsert(makeDevice(ip: "192.168.1.1"))
        await acc.upsert(makeDevice(ip: "192.168.1.2"))
        #expect(await acc.count == 2)
        await acc.reset()
        #expect(await acc.isEmpty)
        #expect(await acc.snapshot().isEmpty)
        #expect(await acc.knownIPs().isEmpty)
        #expect(await acc.contains(ip: "192.168.1.1") == false)
    }
}
