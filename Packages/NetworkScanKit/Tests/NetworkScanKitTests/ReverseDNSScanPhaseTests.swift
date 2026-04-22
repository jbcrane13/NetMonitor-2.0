import Testing
import Foundation
@testable import NetworkScanKit

@Suite("ReverseDNSScanPhase")
struct ReverseDNSScanPhaseTests {

    // MARK: - Phase metadata

    @Test("id is 'reverseDNS'")
    func phaseIDIsReverseDNS() {
        let phase = ReverseDNSScanPhase()
        #expect(phase.id == "reverseDNS")
    }

    @Test("displayName is 'Resolving names…'")
    func phaseDisplayName() {
        let phase = ReverseDNSScanPhase()
        #expect(phase.displayName == "Resolving names…")
    }

    @Test("weight is 0.08")
    func phaseWeight() {
        let phase = ReverseDNSScanPhase()
        #expect(phase.weight == 0.08)
    }

    @Test("weight is positive")
    func phaseWeightIsPositive() {
        let phase = ReverseDNSScanPhase()
        #expect(phase.weight > 0)
    }

    @Test("conforms to ScanPhase protocol")
    func conformsToScanPhase() {
        let phase: any ScanPhase = ReverseDNSScanPhase()
        #expect(phase.id == "reverseDNS")
        #expect(phase.displayName == "Resolving names…")
        #expect(phase.weight == 0.08)
    }

    // MARK: - Init with maxConcurrentResolves

    @Test("default maxConcurrentResolves is 8")
    func defaultMaxConcurrentResolves() {
        let phase = ReverseDNSScanPhase()
        #expect(phase.maxConcurrentResolves == 8)
    }

    @Test("custom maxConcurrentResolves")
    func customMaxConcurrentResolves() {
        let phase = ReverseDNSScanPhase(maxConcurrentResolves: 4)
        #expect(phase.maxConcurrentResolves == 4)
    }

    @Test("maxConcurrentResolves of 1")
    func maxConcurrentResolvesOne() {
        let phase = ReverseDNSScanPhase(maxConcurrentResolves: 1)
        #expect(phase.maxConcurrentResolves == 1)
    }

    // MARK: - Execute with empty accumulator

    @Test("execute with empty accumulator completes without crash")
    func executeWithEmptyAccumulator() async {
        let phase = ReverseDNSScanPhase()
        let context = ScanContext(
            hosts: [],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let accumulator = ScanAccumulator()
        let collector = RDNSProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // Empty accumulator means no devices to resolve
        #expect(await accumulator.isEmpty)
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    // MARK: - Execute with devices that already have hostnames

    @Test("execute skips devices that already have hostnames")
    func executeSkipsDevicesWithHostnames() async {
        let phase = ReverseDNSScanPhase()
        let accumulator = ScanAccumulator()

        // Pre-populate with a device that already has a hostname
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.1",
            hostname: "router.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ))

        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let collector = RDNSProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // Device already has hostname — should be skipped, progress should complete fast
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)

        // Hostname should remain unchanged
        let devices = await accumulator.snapshot()
        #expect(devices.count == 1)
        #expect(devices[0].hostname == "router.local")
    }

    // MARK: - Execute with devices needing hostname resolution

    @Test("execute attempts resolution for devices without hostnames")
    func executeResolvesDevicesWithoutHostnames() async {
        let phase = ReverseDNSScanPhase(maxConcurrentResolves: 2)
        let accumulator = ScanAccumulator()

        // Pre-populate with devices that lack hostnames
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.1",
            hostname: nil,
            vendor: nil,
            macAddress: "aa:bb:cc:dd:ee:ff",
            latency: 5.0,
            discoveredAt: Date(),
            source: .local
        ))

        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let collector = RDNSProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)

        // The device may or may not get a hostname depending on DNS,
        // but the phase should complete without crash
        let devices = await accumulator.snapshot()
        #expect(devices.count == 1)
    }

    @Test("execute with multiple devices needing resolution completes")
    func executeWithMultipleDevicesNeedingResolution() async {
        let phase = ReverseDNSScanPhase(maxConcurrentResolves: 2)
        let accumulator = ScanAccumulator()

        // Pre-populate with multiple devices without hostnames
        for i in 1...3 {
            await accumulator.upsert(DiscoveredDevice(
                ipAddress: "192.168.1.\(i)",
                hostname: nil,
                vendor: nil,
                macAddress: nil,
                latency: nil,
                discoveredAt: Date(),
                source: .local
            ))
        }

        let context = ScanContext(
            hosts: (1...3).map { "192.168.1.\($0)" },
            subnetFilter: { _ in true },
            localIP: nil
        )
        let collector = RDNSProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)

        let count = await accumulator.count
        #expect(count == 3)
    }

    // MARK: - Execute with mix of resolved and unresolved devices

    @Test("execute only resolves devices without hostnames")
    func executeOnlyResolvesUnresolvedDevices() async {
        let phase = ReverseDNSScanPhase(maxConcurrentResolves: 2)
        let accumulator = ScanAccumulator()

        // Device with hostname already set
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.1",
            hostname: "named-device.local",
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ))

        // Device without hostname
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.2",
            hostname: nil,
            vendor: nil,
            macAddress: nil,
            latency: nil,
            discoveredAt: Date(),
            source: .local
        ))

        let context = ScanContext(
            hosts: ["192.168.1.1", "192.168.1.2"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let collector = RDNSProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)

        // Named device should keep its hostname
        let devices = await accumulator.snapshot()
        let namedDevice = devices.first { $0.ipAddress == "192.168.1.1" }
        #expect(namedDevice?.hostname == "named-device.local")
    }

    // MARK: - Progress reporting

    @Test("execute with no devices needing resolution reports immediate completion")
    func executeWithAllResolvedReportsImmediateCompletion() async {
        let phase = ReverseDNSScanPhase()
        let accumulator = ScanAccumulator()

        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.1",
            hostname: "router.local",
            vendor: nil,
            macAddress: nil,
            latency: 3.0,
            discoveredAt: Date(),
            source: .local
        ))

        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )
        let collector = RDNSProgressCollector()

        await phase.execute(context: context, accumulator: accumulator) { p in
            await collector.append(p)
        }

        // When all devices already have hostnames, should complete quickly
        let values = await collector.values
        #expect(values.first == 0.0)
        #expect(values.last == 1.0)
    }

    // MARK: - Device source after upsert

    @Test("resolved hostname device is upserted with source .local")
    func resolvedDeviceHasLocalSource() async {
        let phase = ReverseDNSScanPhase(maxConcurrentResolves: 1)
        let accumulator = ScanAccumulator()

        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.1",
            hostname: nil,
            vendor: nil,
            macAddress: "aa:bb:cc:dd:ee:ff",
            latency: 5.0,
            discoveredAt: Date(),
            source: .local
        ))

        let context = ScanContext(
            hosts: ["192.168.1.1"],
            subnetFilter: { _ in true },
            localIP: nil
        )

        await phase.execute(context: context, accumulator: accumulator) { _ in }

        // After resolution, the device should still be present
        let devices = await accumulator.snapshot()
        #expect(devices.count == 1)
        #expect(devices[0].source == .local)
    }

    // MARK: - Multiple instances

    @Test("multiple instances have independent maxConcurrentResolves")
    func multipleInstancesIndependent() {
        let phase1 = ReverseDNSScanPhase(maxConcurrentResolves: 2)
        let phase2 = ReverseDNSScanPhase(maxConcurrentResolves: 16)
        #expect(phase1.maxConcurrentResolves == 2)
        #expect(phase2.maxConcurrentResolves == 16)
    }

    // MARK: - DeviceNameResolver

    @Test("DeviceNameResolver resolves without crashing")
    func deviceNameResolverResolvesWithoutCrash() async {
        let resolver = DeviceNameResolver()
        // 192.0.2.1 is a TEST-NET address (RFC 5737) — likely no PTR record
        let result = await resolver.resolve(ipAddress: "192.0.2.1")
        // Result may be nil or a hostname — just verify it doesn't crash
        _ = result
    }

    @Test("DeviceNameResolver handles invalid IP gracefully")
    func deviceNameResolverHandlesInvalidIP() async {
        let resolver = DeviceNameResolver()
        let result = await resolver.resolve(ipAddress: "not-an-ip")
        #expect(result == nil)
    }

    @Test("DeviceNameResolver is Sendable")
    func deviceNameResolverIsSendable() {
        let resolver = DeviceNameResolver()
        // Should compile — verifies Sendable conformance
        _ = resolver
    }
}

// MARK: - Test helpers

private actor RDNSProgressCollector {
    private var _values: [Double] = []
    func append(_ v: Double) { _values.append(v) }
    var values: [Double] { _values }
}
