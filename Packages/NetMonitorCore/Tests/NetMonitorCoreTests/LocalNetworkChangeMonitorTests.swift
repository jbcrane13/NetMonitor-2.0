import Foundation
import Testing
@testable import NetMonitorCore

@MainActor
struct LocalNetworkChangeMonitorTests {
    @Test("Joining a new network calls onChange with the new local profile")
    func newNetworkCallsOnChange() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let changes = ChangeRecorder()
        let monitor = fixture.makeMonitor { changes.profiles.append($0) }

        fixture.box.value = [fixture.away]
        #expect(monitor.handlePathSettled(satisfied: true))
        #expect(changes.profiles.count == 1)
        #expect(changes.profiles.first?.subnet == "10.0.0.0/24")
    }

    @Test("A settled path on the same network does nothing")
    func sameNetworkDoesNothing() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let changes = ChangeRecorder()
        let monitor = fixture.makeMonitor { changes.profiles.append($0) }

        #expect(!monitor.handlePathSettled(satisfied: true))
        #expect(!monitor.checkNow())
        #expect(changes.profiles.isEmpty)
    }

    @Test("An unsatisfied path does nothing")
    func unsatisfiedPathDoesNothing() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let changes = ChangeRecorder()
        let monitor = fixture.makeMonitor { changes.profiles.append($0) }

        fixture.box.value = [fixture.away]
        #expect(!monitor.handlePathSettled(satisfied: false))
        #expect(changes.profiles.isEmpty)
    }

    @Test("A change is still reported after another caller re-detected the network first")
    func changeSeenAfterOtherCallerDetected() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let changes = ChangeRecorder()
        let monitor = fixture.makeMonitor { changes.profiles.append($0) }

        fixture.box.value = [fixture.away]
        fixture.manager.detectLocalNetwork() // e.g. a view model refreshing on its own
        #expect(monitor.checkNow())
        #expect(changes.profiles.count == 1)
        #expect(!monitor.checkNow(), "The same change is reported once")
    }

    @Test("Returning home is reported as a change too")
    func returningHomeIsAChange() {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let changes = ChangeRecorder()
        let monitor = fixture.makeMonitor { changes.profiles.append($0) }

        fixture.box.value = [fixture.away]
        monitor.checkNow()
        fixture.box.value = [fixture.home]
        monitor.checkNow()
        #expect(changes.profiles.map(\.subnet) == ["10.0.0.0/24", "192.168.1.0/24"])
    }

    @Test("A burst of path updates settles into one detection")
    func burstIsDebounced() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
        let changes = ChangeRecorder()
        let monitor = LocalNetworkChangeMonitor(
            profileManager: fixture.manager,
            pathEvents: stream,
            debounce: .milliseconds(100)
        ) { changes.profiles.append($0) }
        monitor.start()
        defer { monitor.stop() }

        fixture.box.value = [fixture.away]
        continuation.yield(false)
        continuation.yield(true)
        continuation.yield(true)
        continuation.yield(true)

        for _ in 0..<40 where changes.profiles.isEmpty {
            try? await Task.sleep(for: .milliseconds(50))
        }
        try? await Task.sleep(for: .milliseconds(300))
        #expect(changes.profiles.count == 1)
        continuation.finish()
    }

    // MARK: - Fixture

    @MainActor
    private struct Fixture {
        let suiteName = "LocalNetworkChangeMonitorTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let box: MonitorProfileBox
        let manager: NetworkProfileManager
        let home: NetworkProfile
        let away: NetworkProfile

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            home = NetworkProfile(
                interfaceName: "en0", ipAddress: "192.168.1.10",
                network: Self.network("192.168.1.0", prefix: 24), connectionType: .wifi
            )
            away = NetworkProfile(
                interfaceName: "en0", ipAddress: "10.0.0.5",
                network: Self.network("10.0.0.0", prefix: 24), connectionType: .wifi
            )
            let box = MonitorProfileBox([home])
            self.box = box
            manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { box.value })
            manager.detectLocalNetwork()
        }

        func makeMonitor(onChange: @escaping @MainActor (NetworkProfile) -> Void) -> LocalNetworkChangeMonitor {
            let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
            continuation.finish()
            return LocalNetworkChangeMonitor(
                profileManager: manager,
                pathEvents: stream,
                debounce: .milliseconds(10),
                onChange: onChange
            )
        }

        func tearDown() {
            defaults.removePersistentDomain(forName: suiteName)
        }

        private static func network(_ address: String, prefix: Int) -> NetworkUtilities.IPv4Network {
            let raw = NetworkUtilities.ipv4ToUInt32(address) ?? 0
            let netmask: UInt32 = prefix == 0 ? 0 : UInt32.max << UInt32(32 - prefix)
            let networkAddress = raw & netmask
            return NetworkUtilities.IPv4Network(
                networkAddress: networkAddress,
                broadcastAddress: networkAddress | ~netmask,
                interfaceAddress: networkAddress &+ 2,
                netmask: netmask
            )
        }
    }
}

@MainActor
private final class ChangeRecorder {
    var profiles: [NetworkProfile] = []
}

/// Mutable interface list behind NetworkProfileManager's `@Sendable` provider.
private final class MonitorProfileBox: @unchecked Sendable {
    private let lock = NSLock()
    private var profiles: [NetworkProfile]

    init(_ profiles: [NetworkProfile]) {
        self.profiles = profiles
    }

    var value: [NetworkProfile] {
        get { lock.withLock { profiles } }
        set { lock.withLock { profiles = newValue } }
    }
}
