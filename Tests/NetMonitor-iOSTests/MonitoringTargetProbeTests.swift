import Testing
@testable import NetMonitor_iOS
import Foundation
import NetMonitorCore

/// The ports a stub device answers on; records every port asked.
private final class MockProbeDevice: @unchecked Sendable {
    private let lock = NSLock()
    private var listening: Set<Int>
    private(set) var asked: [Int] = []

    init(listening: Set<Int>) { self.listening = listening }

    func stopAnswering() { lock.withLock { listening = [] } }

    func connect(_ port: Int) -> Bool {
        lock.withLock {
            asked.append(port)
            return listening.contains(port)
        }
    }
}

/// #572: background checks connect to the target's port, a port a scan found open.
@Suite("Monitoring target probe (#572)")
@MainActor
struct MonitoringTargetProbeTests {
    private func probe(_ device: MockProbeDevice) -> MonitoringTargetProbe {
        MonitoringTargetProbe { _, port, _ in device.connect(port) }
    }

    /// A NAS with port 80 closed and 445 open: up, then down after it stops answering.
    @Test func aReachableDeviceWithPort80ClosedIsUpAndGoesDownWhenItStopsAnswering() async {
        let nas = MockProbeDevice(listening: [445])
        let target = MonitoringTarget(name: "NAS", host: "192.168.1.40", port: 445, targetProtocol: .tcp)
        let check = probe(nas)

        let first = await check.check(target)
        #expect(first.success)
        #expect(first.latency != nil)
        target.recordSuccess(latency: first.latency ?? 0)
        #expect(target.isOnline)

        nas.stopAnswering()
        for _ in 0 ..< 3 {
            let result = await check.check(target)
            #expect(!result.success)
            target.recordFailure()
        }
        #expect(!target.isOnline)
        #expect(Set(nas.asked) == [445], "Only the scanned port is probed, never 80")
    }

    @Test func aTargetSavedWithoutAPortStillProbesPort80() async {
        let web = MockProbeDevice(listening: [80])
        let target = MonitoringTarget(name: "Router", host: "192.168.1.1")
        #expect(MonitoringTargetProbe.port(for: target) == 80)
        #expect(await probe(web).check(target).success)
    }
}
