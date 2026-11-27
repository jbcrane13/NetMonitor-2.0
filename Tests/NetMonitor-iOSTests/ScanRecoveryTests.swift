import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_iOS

/// #628 (lead verification on #633): the iPhone's replacement scan and its network check.
@Suite("Scan recovery")
@MainActor
struct ScanRecoveryTests {
    private static func profile(_ name: String, local: Bool) -> NetworkProfile {
        NetworkProfile(
            id: UUID(), interfaceName: local ? "en0" : "manual-10.9.0.1", ipAddress: "10.9.0.1",
            network: NetworkUtilities.IPv4Network(
                networkAddress: 0x0A09_0000, broadcastAddress: 0x0A09_00FF, interfaceAddress: 0x0A09_0001, netmask: 0xFFFF_FF00
            ),
            connectionType: .wifi, name: name, gatewayIP: "10.9.0.1", subnet: "10.9.0.0/24", isLocal: local,
            discoveryMethod: local ? .auto : .manual
        )
    }

    @Test func aReplacementScansTheManualNetworkTheDroppedScanScanned() async {
        let recovery = ScanRecovery(generation: JoinGeneration(), quietSleep: { _ in }, isActive: { true })
        var scanned: [NetworkProfile?] = []
        recovery.rescan = { scanned.append($0) }
        let manual = Self.profile("Office", local: false)
        recovery.scanDropped(manual)
        await waitUntil { scanned.count == 1 }
        #expect(scanned.first??.id == manual.id)
    }

    @Test func aLocalNetworkIsDetectedAgainForItsReplacement() async {
        let recovery = ScanRecovery(generation: JoinGeneration(), quietSleep: { _ in }, isActive: { true })
        var scanned: [NetworkProfile?] = []
        recovery.rescan = { scanned.append($0) }
        recovery.scanDropped(Self.profile("Home", local: true))
        await waitUntil { scanned.count == 1 }
        #expect(scanned == [nil], "nil: the network the phone is on now")
    }

    @Test func anAttemptIsNotSpentWhenTheAppLeftTheForeground() async {
        var active = true
        let recovery = ScanRecovery(
            generation: JoinGeneration(), quietSleep: { _ in try? await Task.sleep(for: .milliseconds(50)) }, isActive: { active }
        )
        var scanned = 0
        recovery.rescan = { _ in scanned += 1 }
        recovery.scanDropped(nil)
        active = false
        await waitUntil { recovery.attempts == 0 }
        #expect(scanned == 0)
        #expect(recovery.attempts == 0)
    }

    /// Lead verification on #633: the check is set in `App.init`, before any scene, task or intent
    /// can commit; a token for the network the phone is on counts, one it left doesn't.
    @Test func theAppsNetworkCheckFollowsTheCurrentNetwork() {
        let clock = NetworkJoinClock(changes: AsyncStream<String>.makeStream().stream)
        let here = UUID()
        NetmonitorApp.configureJoinClock(clock) { $0 == here }
        #expect(clock.isCurrent(clock.token(for: here)))
        #expect(!clock.isCurrent(clock.token(for: UUID())))
    }
}

@MainActor
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
