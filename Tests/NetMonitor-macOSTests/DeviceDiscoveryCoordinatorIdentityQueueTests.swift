import Foundation
import NetMonitorCore
import NetworkScanKit
import SwiftData
import Testing
@testable import NetMonitor_macOS

/// #645: scans asked for while identifying, and the probe's ownership of the Bonjour browser.
extension DeviceDiscoveryCoordinatorIdentityTests {
    /// Saved rows for a legacy network that this network's answers won't clearly match.
    func seedLegacyRows(_ setup: Setup, _ legacy: UUID) throws {
        for (ip, name) in [("192.168.1.1", "rt-ax86u-7c10"), ("192.168.1.20", "office-printer"), ("192.168.1.30", "backup-nas")] {
            setup.context.insert(LocalDevice(ipAddress: ip, macAddress: "", hostname: name, networkProfileID: legacy))
        }
        try setup.context.save()
    }

    /// #645 verification item 6: a user's scan of a manual network asked for during identification
    /// runs for that network afterwards, not as a scan of the local one.
    @Test func aManualNetworkScanAskedForDuringIdentificationRunsForThatNetwork() async throws {
        let box = Box()
        let legacy = UUID()
        box.hint = .present(keyA)
        box.holds = true
        let setup = try setUp(box, legacy: ["en0|192.168.1.0/24": legacy])
        let lab = try #require(setup.manager.addProfile(gateway: "10.0.0.1", subnet: "10.0.0.0/24", name: "Lab"))
        await waitUntil { box.gates.count == 1 }
        #expect(!setup.coordinator.rescan(.user(lab)))
        box.devices = [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.20", "lab-printer")]
        box.release()
        await waitUntil { setup.coordinator.lastScanTime(for: lab.id) != nil }
        #expect(setup.coordinator.lastScanTime(for: lab.id) != nil, "the lab was scanned")
    }

    /// Round 4 item 1: at a new same-subnet site the probe runs under tentative ID L; ⌘R is queued;
    /// the user answers "New network" (N). The replayed scan is N's: nothing is saved into L.
    @Test func aReplayedScanNeverSavesIntoTheTentativeLegacyNetwork() async throws {
        let box = Box()
        let legacy = UUID()
        box.hint = .present(keyA)
        box.holds = true
        let setup = try setUp(box, legacy: ["en0|192.168.1.0/24": legacy])
        try seedLegacyRows(setup, legacy)
        await waitUntil { box.gates.count == 1 }
        let tentative = try #require(setup.manager.localProfile)
        #expect(tentative.id == legacy)
        #expect(!setup.coordinator.rescan(.user(tentative)))
        box.devices = [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "someone-elses-printer")]
        box.release()
        await setup.identity.probeTask?.value
        let question = try #require(setup.identity.question)
        setup.identity.answer(.newNetwork, to: question)
        setup.manager.detectLocalNetwork()
        let siteN = setup.local
        #expect(siteN != legacy)
        await waitUntil { setup.coordinator.lastScanTime(for: siteN) != nil }
        #expect(setup.coordinator.lastScanTime(for: siteN) != nil, "one scan saved into N")
        #expect(setup.coordinator.lastScanTime(for: legacy) == nil, "nothing saved into L")
        let legacyRows = try setup.context.fetch(FetchDescriptor<LocalDevice>(predicate: #Predicate { $0.networkProfileID == legacy }))
        #expect(Set(legacyRows.compactMap(\.hostname)) == ["rt-ax86u-7c10", "office-printer", "backup-nas"])
        // And underneath: a scan under an ID that was only ever tentative for this connection never commits.
        let commit = setup.coordinator.commitScan(
            [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "x")], profileID: legacy, now: Date(),
            token: setup.join.token(for: nil)
        )
        #expect(commit == .held)
    }

    /// Round 4 items 2 and 3: a manual network's scan asked for twice during an unclear probe runs
    /// once, when the probe ends (the question still open), and the local network still gets its
    /// scan once identified.
    @Test func aManualScanQueuedDuringAnUnclearProbeRunsOnceAtTheProbesEnd() async throws {
        let box = Box()
        let legacy = UUID()
        box.hint = .present(keyA)
        box.holds = true
        let setup = try setUp(box, legacy: ["en0|192.168.1.0/24": legacy])
        try seedLegacyRows(setup, legacy)
        let lab = try #require(setup.manager.addProfile(gateway: "10.0.0.1", subnet: "10.0.0.0/24", name: "Lab"))
        await waitUntil { box.gates.count == 1 }
        #expect(!setup.coordinator.rescan(.user(lab)))
        #expect(!setup.coordinator.rescan(.user(lab)))
        box.devices = [DeviceDiscoveryCoordinatorReconcileTests.engine("10.0.0.20", "lab-printer")]
        box.release()
        await setup.identity.probeTask?.value
        #expect(setup.identity.question != nil, "the probe was unclear")
        await waitUntil { setup.coordinator.lastScanTime(for: lab.id) != nil }
        #expect(setup.coordinator.lastScanTime(for: lab.id) != nil, "the lab ran while the question was open")
        await waitUntil { !setup.coordinator.isScanning }
        #expect(box.scans == 2, "the probe and one lab scan")

        box.devices = [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "office-printer")]
        try setup.identity.answer(.same(legacy), to: #require(setup.identity.question))
        setup.manager.detectLocalNetwork()
        await waitUntil { setup.coordinator.lastScanTime(for: legacy) != nil }
        await waitUntil { !setup.coordinator.isScanning }
        #expect(setup.coordinator.lastScanTime(for: legacy) != nil, "the local network's scan once identified")
        #expect(box.scans == 3, "the lab once, the local network once")
    }

    /// The Bonjour guard: a pipeline whose run is obsolete doesn't stop the shared browser.
    @Test func anObsoletePipelineDoesNotStopTheSharedBonjourBrowser() async throws {
        let box = Box()
        let setup = try setUp(box)
        _ = setup.coordinator.makePipeline { false }
        let inputs = try #require(box.lastInputs)
        setup.coordinator.bonjourScanner.startDiscovery()
        await inputs.bonjourStopProvider()
        #expect(setup.coordinator.bonjourScanner.isDiscovering)
        _ = setup.coordinator.makePipeline { true }
        try await (#require(box.lastInputs)).bonjourStopProvider()
        #expect(!setup.coordinator.bonjourScanner.isDiscovering)
    }

    /// A path update overtakes the probe: the newer probe owns the Bonjour browser and the result, and
    /// once the network is identified exactly one scan runs and is saved (#645).
    @Test func aPathUpdateDuringTheProbeLeadsToExactlyOneSavedScan() async throws {
        let box = Box()
        let legacy = UUID()
        box.hint = .present(keyA)
        box.holds = true
        let setup = try setUp(box, legacy: ["en0|192.168.1.0/24": legacy])
        await waitUntil { box.gates.count == 1 }
        setup.join.generation.advance()
        setup.manager.detectLocalNetwork()
        await waitUntil { box.gates.count == 2 }
        #expect(setup.coordinator.isIdentifyingNetwork)
        // A scan asked for meanwhile is refused, then runs once identification ends.
        #expect(!setup.coordinator.rescan(.networkChanged))
        // The obsolete probe finishes first: it must not end the newer one's run (its Bonjour browser).
        box.gates.removeFirst().resume()
        for _ in 0 ..< 50 {
            await Task.yield()
        }
        #expect(setup.coordinator.isProbing, "the newer probe still owns the run")
        box.devices = [DeviceDiscoveryCoordinatorReconcileTests.engine("192.168.1.20", "office-printer")]
        box.release()
        await waitUntil { setup.coordinator.lastScanTime(for: legacy) != nil }
        #expect(setup.identity.authorizes(legacy))
        await waitUntil(timeout: .seconds(3)) { box.scans > 3 }
        #expect(box.scans == 3, "two probes and one scan")
        await waitUntil { !setup.coordinator.isScanning }
        #expect(!setup.coordinator.isIdentifyingNetwork)
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(10), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
