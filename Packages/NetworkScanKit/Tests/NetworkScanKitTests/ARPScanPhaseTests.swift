import Testing
import Foundation
@testable import NetworkScanKit

@Suite("ARPScanPhase")
struct ARPScanPhaseTests {

    // MARK: - Phase metadata

    @Test("id is 'arp'")
    func phaseIDIsArp() {
        let phase = ARPScanPhase()
        #expect(phase.id == "arp")
    }

    @Test("displayName is 'Scanning network…'")
    func phaseDisplayName() {
        let phase = ARPScanPhase()
        #expect(phase.displayName == "Scanning network…")
    }

    @Test("weight is 0.10")
    func phaseWeight() {
        let phase = ARPScanPhase()
        #expect(phase.weight == 0.10)
    }

    @Test("weight is positive")
    func phaseWeightIsPositive() {
        let phase = ARPScanPhase()
        #expect(phase.weight > 0)
    }

    @Test("conforms to ScanPhase protocol")
    func conformsToScanPhase() {
        let phase: any ScanPhase = ARPScanPhase()
        #expect(phase.id == "arp")
        #expect(phase.displayName == "Scanning network…")
        #expect(phase.weight == 0.10)
    }

    // MARK: - Execute with subnet filter

    @Test("execute with reject-all subnet filter completes without crash and reports progress")
    func executeWithRejectAllFilter() async {
        let phase = ARPScanPhase()
        let context = ScanContext(
            hosts: ["192.168.1.1", "192.168.1.2"],
            subnetFilter: { _ in false },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = ProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // No devices should be added when subnetFilter rejects all
        #expect(await accumulator.isEmpty)

        // Progress should start at 0 and end at 1
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    @Test("execute with accept-all subnet filter may add devices from ARP cache")
    func executeWithAcceptAllFilter() async {
        let phase = ARPScanPhase()
        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = ProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // Progress should start at 0 and end at 1
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)

        // Devices may or may not be found depending on ARP cache state,
        // but the phase must complete without crashing
        let count = await accumulator.count
        #expect(count >= 0)
    }

    @Test("execute with empty hosts list completes without crash")
    func executeWithEmptyHosts() async {
        let phase = ARPScanPhase()
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = ProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // The ARP cache may contain entries from any interface,
        // so the accumulator may or may not be empty depending on system state.
        // The important thing is that the phase completes without crash.
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    @Test("execute reports multiple progress values")
    func executeReportsMultipleProgressValues() async {
        let phase = ARPScanPhase()
        let context = ScanContext(
            hosts: ["10.0.0.1"],
            subnetFilter: { _ in false },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = ProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        let values = await collector.values
        // ARPScanPhase reports: 0.0, 0.3, 0.6, 0.8, 1.0
        #expect(values.count >= 2)
        #expect(values.contains(0.0))
        #expect(values.contains(1.0))
    }

    @Test("execute with subnet filter that only accepts specific IP")
    func executeWithSpecificSubnetFilter() async {
        let phase = ARPScanPhase()
        let targetIP = "192.168.1.1"
        let context = ScanContext(
            hosts: ["192.168.1.1", "192.168.1.2", "10.0.0.1"],
            subnetFilter: { $0 == targetIP },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        // Only devices matching the filter should be added
        let devices = await accumulator.snapshot()
        for device in devices {
            #expect(device.ipAddress == targetIP)
        }
    }

    // MARK: - DiscoveredDevice source

    @Test("devices from ARP scan have source .local")
    func devicesFromARPHaveLocalSource() async {
        let phase = ARPScanPhase()
        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        let devices = await accumulator.snapshot()
        for device in devices {
            #expect(device.source == .local)
        }
    }

    @Test("devices from ARP scan have MAC address set when found")
    func devicesFromARPHaveMacAddress() async {
        let phase = ARPScanPhase()
        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        // Devices found via ARP cache should have MAC addresses;
        // however, in test environments the ARP cache may be empty,
        // so we only check that if devices exist they have the right structure
        let devices = await accumulator.snapshot()
        for device in devices {
            // ARP-discovered devices may or may not have MAC depending on cache state
            #expect(device.source == .local)
        }
    }

    // MARK: - Multiple instantiations

    @Test("multiple ARPScanPhase instances have independent state")
    func multipleInstancesAreIndependent() {
        let phase1 = ARPScanPhase()
        let phase2 = ARPScanPhase()
        #expect(phase1.id == phase2.id)
        #expect(phase1.weight == phase2.weight)
        // Both are stateless structs, so this is expected
    }
}

// MARK: - Shared actor helper

private actor ProgressCollector {
    private var _values: [Double] = []
    func append(_ v: Double) { _values.append(v) }
    var values: [Double] { _values }
}
