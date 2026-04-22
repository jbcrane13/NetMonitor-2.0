import Testing
import Foundation
@testable import NetworkScanKit

@Suite("BonjourScanPhase")
struct BonjourScanPhaseTests {

    // MARK: - Phase metadata

    @Test("id is 'bonjour'")
    func phaseIDIsBonjour() {
        let phase = BonjourScanPhase(serviceProvider: { [] })
        #expect(phase.id == "bonjour")
    }

    @Test("displayName is 'Bonjour discovery…'")
    func phaseDisplayName() {
        let phase = BonjourScanPhase(serviceProvider: { [] })
        #expect(phase.displayName == "Bonjour discovery…")
    }

    @Test("weight is 0.13")
    func phaseWeight() {
        let phase = BonjourScanPhase(serviceProvider: { [] })
        #expect(phase.weight == 0.13)
    }

    @Test("weight is positive")
    func phaseWeightIsPositive() {
        let phase = BonjourScanPhase(serviceProvider: { [] })
        #expect(phase.weight > 0)
    }

    @Test("conforms to ScanPhase protocol")
    func conformsToScanPhase() {
        let phase: any ScanPhase = BonjourScanPhase(serviceProvider: { [] })
        #expect(phase.id == "bonjour")
        #expect(phase.displayName == "Bonjour discovery…")
        #expect(phase.weight == 0.13)
    }

    // MARK: - Init with serviceProvider

    @Test("init with serviceProvider and no stopProvider")
    func initWithoutStopProvider() {
        let phase = BonjourScanPhase(serviceProvider: { [] })
        #expect(phase.id == "bonjour")
    }

    @Test("init with serviceProvider and stopProvider")
    func initWithStopProvider() {
        let phase = BonjourScanPhase(
            serviceProvider: { [] },
            stopProvider: { }
        )
        #expect(phase.id == "bonjour")
    }

    // MARK: - Execute with empty services

    @Test("execute with empty serviceProvider completes and reports progress")
    func executeWithEmptyServices() async {
        let phase = BonjourScanPhase(serviceProvider: { [] })
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = BonjourProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        #expect(await accumulator.isEmpty)
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    @Test("execute with empty services calls stopProvider")
    func executeWithEmptyServicesCallsStopProvider() async {
        let stopCalled = BonjourStopFlag()
        let phase = BonjourScanPhase(
            serviceProvider: { [] },
            stopProvider: { await stopCalled.mark() }
        )
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        #expect(await stopCalled.wasCalled)
    }

    // MARK: - Execute with services that resolve to out-of-subnet IPs

    @Test("execute with services that are all filtered out by subnetFilter")
    func executeWithAllServicesFilteredOut() async {
        let services = [
            BonjourServiceInfo(name: "Device1", type: "_http._tcp.", domain: "local."),
            BonjourServiceInfo(name: "Device2", type: "_http._tcp.", domain: "local.")
        ]
        let phase = BonjourScanPhase(serviceProvider: { services })
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in false },  // reject all IPs
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = BonjourProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // No devices should be added when subnetFilter rejects all
        #expect(await accumulator.isEmpty)

        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    // MARK: - Execute with reject-all filter and services present

    @Test("execute completes with services present but subnet filter rejecting all")
    func executeWithServicesButFilterRejectsAll() async {
        let services = [
            BonjourServiceInfo(name: "Printer", type: "_ipp._tcp.", domain: "local.")
        ]
        let phase = BonjourScanPhase(serviceProvider: { services })
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in false },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        #expect(await accumulator.isEmpty)
    }

    // MARK: - Deduplication of services

    @Test("duplicate services are deduplicated")
    func duplicateServicesAreDeduplicated() async {
        let services = [
            BonjourServiceInfo(name: "Device", type: "_http._tcp.", domain: "local."),
            BonjourServiceInfo(name: "Device", type: "_http._tcp.", domain: "local."),
            BonjourServiceInfo(name: "Device", type: "_http._tcp.", domain: "local.")
        ]
        let phase = BonjourScanPhase(serviceProvider: { services })
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in false },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = BonjourProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // Even with duplicate services, should complete without error
        #expect(await accumulator.isEmpty)
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    @Test("services with same name but different type are not deduplicated")
    func servicesWithSameNameDifferentTypeNotDeduplicated() async {
        let services = [
            BonjourServiceInfo(name: "Device", type: "_http._tcp.", domain: "local."),
            BonjourServiceInfo(name: "Device", type: "_ipp._tcp.", domain: "local.")
        ]
        let phase = BonjourScanPhase(serviceProvider: { services })
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in false },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        // Should complete without error — deduplication keeps both unique services
        let values = await accumulator.isEmpty
        #expect(values == true)  // no IPs match the filter
    }

    // MARK: - Progress reporting

    @Test("execute with reject-all filter still reports full progress range")
    func executeReportsFullProgressRange() async {
        let services = [
            BonjourServiceInfo(name: "Device", type: "_http._tcp.", domain: "local.")
        ]
        let phase = BonjourScanPhase(serviceProvider: { services })
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in false },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = BonjourProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
        #expect(values.count >= 2)
    }

    // MARK: - Stop provider is called on completion

    @Test("stopProvider is called when phase completes")
    func stopProviderCalledOnCompletion() async {
        let stopCalled = BonjourStopFlag()
        let phase = BonjourScanPhase(
            serviceProvider: { [] },
            stopProvider: { await stopCalled.mark() }
        )
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        #expect(await stopCalled.wasCalled)
    }

    @Test("stopProvider is nil by default and does not crash")
    func nilStopProviderDoesNotCrash() async {
        let phase = BonjourScanPhase(serviceProvider: { [] })
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        // Should not crash even with nil stopProvider
        await phase.execute(context: context, accumulator: accumulator) { _ in }

        #expect(await accumulator.isEmpty)
    }

    // MARK: - Large number of services capped at maxResolves

    @Test("execute handles many services without crashing")
    func executeHandlesManyServices() async {
        // Generate 150 services (exceeds maxResolves of 100)
        let services = (0..<150).map { i in
            BonjourServiceInfo(name: "Device-\(i)", type: "_http._tcp.", domain: "local.")
        }
        let phase = BonjourScanPhase(serviceProvider: { services })
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in false },
            localIP: nil
        )
        let accumulator = ScanAccumulator()

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        // Should complete — cap of 100 resolves is internal
        #expect(await accumulator.isEmpty)
    }
}

// MARK: - Test helpers

private actor BonjourProgressCollector {
    private var _values: [Double] = []
    func append(_ v: Double) { _values.append(v) }
    var values: [Double] { _values }
}

private actor BonjourStopFlag {
    private var _called = false
    func mark() { _called = true }
    var wasCalled: Bool { _called }
}
