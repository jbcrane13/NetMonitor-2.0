import Testing
import Foundation
import Synchronization
@testable import NetMonitorCore

/// A pinger that answers each host as scripted (#579): reply times (nil for a lost probe), or no
/// answer at all until it is cancelled.
final class MockScriptedPinger: PingServiceProtocol, Sendable {
    enum Reply: Sendable {
        case times([Double?])
        /// The replies after a wait, so a test can act while the probe runs.
        case delayed(Duration, [Double?])
        case hang
    }

    private let replies: [String: Reply]
    private let pinged = Mutex<[String]>([])

    init(_ replies: [String: Reply]) {
        self.replies = replies
    }

    var hosts: [String] { pinged.withLock { $0 } }

    func ping(host: String, count: Int, timeout: TimeInterval) async -> AsyncStream<PingResult> {
        pinged.withLock { $0.append(host) }
        switch replies[host] ?? .times(Array(repeating: nil, count: count)) {
        case let .times(times):
            return AsyncStream { continuation in
                for (index, time) in times.enumerated() {
                    continuation.yield(PingResult(sequence: index + 1, host: host, ttl: 64, time: time ?? 0, isTimeout: time == nil))
                }
                continuation.finish()
            }
        case let .delayed(wait, times):
            return AsyncStream { continuation in
                let task = Task {
                    try? await Task.sleep(for: wait)
                    for (index, time) in times.enumerated() {
                        continuation.yield(PingResult(sequence: index + 1, host: host, ttl: 64, time: time ?? 0, isTimeout: time == nil))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        case .hang:
            return AsyncStream { _ in }
        }
    }

    func stop() async {}

    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? { nil }
}

/// Waits until `condition` holds, at most `timeout`.
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// The fixture network as the live tools see it (#579): 192.168.1.0/24, which the phone is on,
/// joined before the scan at `Fix.now`, which established it.
enum AskLiveFixture {
    typealias Fix = AskFixture

    static let network = NetworkProfile(
        id: UUID(), interfaceName: "en0", ipAddress: "192.168.1.10",
        network: NetworkUtilities.IPv4Network(
            networkAddress: NetworkUtilities.ipv4ToUInt32("192.168.1.0") ?? 0,
            broadcastAddress: NetworkUtilities.ipv4ToUInt32("192.168.1.255") ?? 0,
            interfaceAddress: NetworkUtilities.ipv4ToUInt32("192.168.1.10") ?? 0,
            netmask: 0xFFFF_FF00
        ),
        connectionType: .wifi, name: "Home", gatewayIP: "192.168.1.1", subnet: "192.168.1.0/24", isLocal: true, discoveryMethod: .auto
    )

    static let snapshot = AskSnapshot(
        devices: Fix.devices, events: Fix.events, networkProfileID: network.id, lastScan: Fix.now, now: Fix.now, calendar: Fix.calendar
    )

    /// The time the app stamps on a measurement.
    static let measuredAt = Fix.now.addingTimeInterval(5)
    /// The scan that established the network since the phone joined it: the last one.
    static let established = Fix.now

    final class Flag: Sendable {
        private let value: Mutex<Bool>
        init(_ value: Bool = false) { self.value = Mutex(value) }
        func set(_ new: Bool) { value.withLock { $0 = new } }
        var isSet: Bool { value.withLock { $0 } }
    }

    static func live(
        _ pinger: MockScriptedPinger,
        network: NetworkProfile? = network,
        connection: AskLiveTools.Connection = .init(type: .wifi, gatewayIP: "192.168.1.1"),
        scanning: Flag = Flag(),
        established: Date? = established,
        deadline: Duration = .seconds(5)
    ) -> AskLiveTools {
        AskLiveTools(
            pinger: pinger, currentNetwork: { network }, connection: { connection }, isScanning: { scanning.isSet },
            establishedScan: { established }, now: { measuredAt }, deadline: deadline
        )
    }

    static func toolbox(_ live: AskLiveTools?, snapshot: AskSnapshot = snapshot) -> AskToolbox {
        AskToolbox(snapshot: snapshot, live: live)
    }
}

@Suite("AskToolbox live tools")
struct AskLiveToolsTests {
    typealias Fix = AskFixture
    typealias Live = AskLiveFixture

    // MARK: - pingDevice

    @Test func pingDeviceReportsTheRepliesAndTheAppsAverage() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([3.6, 4.2, 4.2])])
        let toolbox = Live.toolbox(Live.live(pinger))
        let output = await toolbox.pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 (192.168.1.20): 3 of 3 replies, average 4 ms.")
        #expect(pinger.hosts == ["192.168.1.20"])
        #expect(toolbox.record.deviceIDs == [Fix.nas.id])
        #expect(toolbox.record.measurements == [AskMeasurement(
            deviceID: Fix.nas.id, text: "Synology DS920 (192.168.1.20): 3 of 3 replies, 4 ms average", measuredAt: Live.measuredAt
        )])
    }

    @Test func lostProbesCountAgainstTheThreeSent() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([2, nil, 4])])
        let output = await Live.toolbox(Live.live(pinger)).pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 (192.168.1.20): 2 of 3 replies, average 3 ms.")
    }

    @Test func noReplyIsNeverCalledOfflineAndSaysTheScanDisagreed() async {
        let toolbox = Live.toolbox(Live.live(MockScriptedPinger([:])))
        let output = await toolbox.pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 (192.168.1.20): no reply to 3 pings.")
        #expect(toolbox.record.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): no reply to 3 pings"])
        #expect(toolbox.record.measurements.first?.lastScanNote == "At the last scan less than a minute ago it was online.")
    }

    @Test func aPingThatOutlivesTheDeadlineIsNotMeasured() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .hang])
        let toolbox = Live.toolbox(Live.live(pinger, deadline: .milliseconds(100)))
        let output = await toolbox.pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 (192.168.1.20): not measured, the ping didn't finish in time.")
        #expect(toolbox.record.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): not measured, timed out"])
    }

    @Test func aCancelledPingReturnsWithoutAMeasurement() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .hang])
        let toolbox = Live.toolbox(Live.live(pinger, deadline: .seconds(60)))
        let task = Task { await toolbox.pingDevice("dev-b") }
        await waitUntil { !pinger.hosts.isEmpty }
        task.cancel()
        let output = await task.value
        #expect(output.hasSuffix("not measured, cancelled."))
        #expect(toolbox.record.measurements.isEmpty)
    }

    @Test func aDeviceOutsideTheCurrentNetworkIsNotPinged() async {
        let away = Fix.device("Cabin Camera", .camera, ip: "10.0.0.8")
        let snapshot = AskSnapshot(devices: [away], events: [], networkProfileID: Live.network.id, lastScan: Fix.now, now: Fix.now,
                                   calendar: Fix.calendar)
        let pinger = MockScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger), snapshot: snapshot)
        let output = await toolbox.pingDevice("dev-a")
        #expect(output == "Cabin Camera was not pinged: its address is not on the network this device is on now.")
        #expect(pinger.hosts.isEmpty)
        #expect(toolbox.record.measurements == [AskMeasurement(
            deviceID: away.id, text: "Cabin Camera (10.0.0.8): not pinged, not on the network this device is on now", measuredAt: nil
        )])
    }

    @Test func nothingIsPingedOffTheNetworkAskedAbout() async {
        let pinger = MockScriptedPinger([:])
        let other = NetworkProfile(
            id: UUID(), interfaceName: "en0", ipAddress: "192.168.1.10", network: Live.network.network, connectionType: .wifi,
            name: "Office", gatewayIP: "192.168.1.1", subnet: "192.168.1.0/24", isLocal: true, discoveryMethod: .auto
        )
        for network in [nil, other] {
            let output = await Live.toolbox(Live.live(pinger, network: network)).pingDevice("dev-b")
            #expect(output.hasPrefix("Synology DS920 was not pinged"))
        }
        #expect(pinger.hosts.isEmpty)
    }

    /// Codex review of #627: two LANs with one subnet share a profile ID. After a move, nothing
    /// is pinged until a scan of the new network; then the ping runs.
    @Test func aSameSubnetMoveWithNoScanSinceIsRefused() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([2, 2, 2])])
        let movedAfterTheScan = Live.toolbox(Live.live(pinger, established: nil))
        let output = await movedAfterTheScan.pingDevice("dev-b")
        #expect(output == "Run a scan first: this network hasn't been checked since you joined it. Synology DS920 was not pinged.")
        #expect(movedAfterTheScan.record.measurements.map(\.text)
            == ["Synology DS920 (192.168.1.20): not pinged. Run a scan first: this network hasn't been checked since you joined it."])
        #expect(movedAfterTheScan.record.measurements.first?.measuredAt == nil)
        #expect(pinger.hosts.isEmpty)

        let unknownJoin = await Live.toolbox(Live.live(pinger, established: nil)).pingDevice("dev-b")
        #expect(unknownJoin.hasPrefix(AskToolbox.scanFirst))
        let neverScanned = AskSnapshot(devices: Fix.devices, events: [], networkProfileID: Live.network.id, lastScan: nil, now: Fix.now,
                                       calendar: Fix.calendar)
        #expect(await Live.toolbox(Live.live(pinger), snapshot: neverScanned).pingDevice("dev-b").hasPrefix(AskToolbox.scanFirst))
        #expect(pinger.hosts.isEmpty)

        // An earlier scan established it, but the snapshot's last scan is older: refused.
        let olderSnapshot = Live.toolbox(Live.live(pinger, established: Fix.now.addingTimeInterval(60)))
        #expect(await olderSnapshot.pingDevice("dev-b").hasPrefix(AskToolbox.scanFirst))
        // A scan after the move establishes the network.
        let scannedSince = Live.toolbox(Live.live(pinger, established: Fix.now))
        #expect(await scannedSince.pingDevice("dev-b") == "Pinged Synology DS920 (192.168.1.20): 3 of 3 replies, average 2 ms.")
    }

    @Test func aDeviceOfflineAtTheScanIsNotPingedAtItsOldAddress() async {
        let pinger = MockScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger))
        let output = await toolbox.pingDevice("dev-a")
        #expect(output == "Brother HL-L2350DW was not pinged: it didn't answer the last scan; it was last seen at this address 2 hours ago.")
        #expect(toolbox.record.measurements.map(\.text)
            == ["Brother HL-L2350DW (192.168.1.57): not pinged, last seen at this address 2 hours ago"])
        #expect(pinger.hosts.isEmpty)
    }

    /// DHCP gave Alice's phone's address to Bob's TV (#627 review): the scan made Bob's row, and
    /// Alice's stays Online in grace. A reply from that address is Bob's, so Alice isn't pinged.
    @Test func aDeviceWhoseAddressAnotherDeviceHoldsNowIsNotPinged() async {
        let alice = Fix.device("Alice's iPhone", .phone, ip: "192.168.1.50", lastSeen: Fix.now.addingTimeInterval(-600))
        let bob = Fix.device("Bob's TV", .tv, ip: "192.168.1.50")
        let snapshot = AskSnapshot(devices: [alice, bob], events: [], networkProfileID: Live.network.id, lastScan: Fix.now, now: Fix.now,
                                   calendar: Fix.calendar)
        let pinger = MockScriptedPinger(["192.168.1.50": .times([3, 3, 3])])
        let toolbox = Live.toolbox(Live.live(pinger), snapshot: snapshot)
        #expect(await toolbox.pingDevice("Alice's iPhone")
            == "Alice's iPhone was not pinged: another saved device, Bob's TV, has its address now.")
        #expect(toolbox.record.measurements.map(\.text)
            == ["Alice's iPhone (192.168.1.50): not pinged, Bob's TV has this address now"])
        #expect(pinger.hosts.isEmpty)
        // The device that holds the address is pinged.
        #expect(await toolbox.pingDevice("Bob's TV") == "Pinged Bob's TV (192.168.1.50): 3 of 3 replies, average 3 ms.")
        #expect(pinger.hosts == ["192.168.1.50"])
    }

    /// Verification of #627: Online means Online by `PresenceFreshness`: a days-old scan doesn't
    /// qualify, even if it established the network.
    @Test func aDeviceOnlineOnlyInADaysOldScanIsNotPinged() async {
        let old = Fix.now.addingTimeInterval(-2 * 86400)
        let nas = Fix.device("Synology DS920", .storage, ip: "192.168.1.20", lastSeen: old)
        let snapshot = AskSnapshot(devices: [nas], events: [], networkProfileID: Live.network.id, lastScan: old, now: Fix.now,
                                   calendar: Fix.calendar)
        let pinger = MockScriptedPinger(["192.168.1.20": .times([2, 2, 2])])
        let toolbox = Live.toolbox(Live.live(pinger, established: old), snapshot: snapshot)
        #expect(await toolbox.pingDevice("dev-a")
            == "Synology DS920 was not pinged: it didn't answer the last scan; it was last seen at this address 2 days ago.")
        #expect(pinger.hosts.isEmpty)
    }

    /// Verification of #627: DHCP is judged per member row. A group's stale interface at the
    /// address doesn't make the device seen there now someone else's.
    @Test func aGroupsStaleInterfaceAtTheAddressDoesNotRefuse() async {
        let laptop = AskDevice(
            id: UUID(), displayName: "Studio Laptop", deviceType: .laptop, maker: nil, ipAddress: "192.168.1.31",
            status: .online, lastSeen: Fix.now, lastLatency: nil, latencyHistory: [],
            interfaces: [
                AskDevice.Interface(id: UUID(), address: "192.168.1.31", lastSeen: Fix.now),
                AskDevice.Interface(id: UUID(), address: "192.168.1.40", lastSeen: Fix.now.addingTimeInterval(-3600))
            ]
        )
        let printer = Fix.device("Hall Printer", .printer, ip: "192.168.1.40")
        let snapshot = AskSnapshot(devices: [laptop, printer], events: [], networkProfileID: Live.network.id, lastScan: Fix.now,
                                   now: Fix.now, calendar: Fix.calendar)
        let pinger = MockScriptedPinger(["192.168.1.40": .times([3, 3, 3])])
        let toolbox = Live.toolbox(Live.live(pinger), snapshot: snapshot)
        #expect(await toolbox.pingDevice("Hall Printer") == "Pinged Hall Printer (192.168.1.40): 3 of 3 replies, average 3 ms.")
    }

    /// Verification of #627: one waiter's cancellation doesn't cancel the shared check for the
    /// others, and a finished check is cleared from the running table.
    @Test func cancellingOneWaiterLeavesTheSharedCheckRunning() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .delayed(.milliseconds(300), [2, 2, 2])])
        let toolbox = Live.toolbox(Live.live(pinger))
        let first = Task { await toolbox.pingDevice("dev-b") }
        await waitUntil { !pinger.hosts.isEmpty }
        let second = Task { await toolbox.pingDevice("dev-b") }
        try? await Task.sleep(for: .milliseconds(50))
        first.cancel()
        #expect(await second.value == "Pinged Synology DS920 (192.168.1.20): 3 of 3 replies, average 2 ms.")
        _ = await first.value
        #expect(pinger.hosts == ["192.168.1.20"])
        #expect(!toolbox.hasRunningLiveCheck)
    }

    /// Devin review of #627: two calls for one device in one parallel batch probe once.
    @Test func parallelCallsForOneDeviceProbeOnce() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([2, 2, 2])])
        let toolbox = Live.toolbox(Live.live(pinger))
        async let first = toolbox.pingDevice("dev-b")
        async let second = toolbox.pingDevice("dev-b")
        let results = await [first, second]
        #expect(results[0] == results[1])
        #expect(pinger.hosts == ["192.168.1.20"])
        #expect(toolbox.record.measurements.count == 1)
    }

    @Test func parallelConnectionChecksProbeOnce() async {
        let pinger = MockScriptedPinger(["192.168.1.1": .times([2, 2, 2]), AskLiveTools.internetHost: .times([15, 15, 15])])
        let toolbox = Live.toolbox(Live.live(pinger))
        async let first = toolbox.networkStatus()
        async let second = toolbox.networkStatus()
        let results = await [first, second]
        #expect(results[0] == results[1])
        #expect(pinger.hosts.count == 2)
    }

    /// #594: a device of two interfaces is pinged on its current one and named once.
    @Test func aGroupedDeviceIsPingedOnItsCurrentInterface() async {
        let laptop = AskDevice(
            id: UUID(), displayName: "Studio Laptop", deviceType: .laptop, maker: "Apple", ipAddress: "192.168.1.31",
            status: .online, lastSeen: Fix.now, lastLatency: nil, latencyHistory: [],
            addresses: ["192.168.1.31", "192.168.1.30"], memberIDs: [UUID(), UUID()]
        )
        let snapshot = AskSnapshot(devices: [laptop], events: [], networkProfileID: Live.network.id, lastScan: Fix.now, now: Fix.now,
                                   calendar: Fix.calendar)
        let pinger = MockScriptedPinger(["192.168.1.31": .times([5, 5, 5])])
        let toolbox = Live.toolbox(Live.live(pinger), snapshot: snapshot)
        #expect(await toolbox.pingDevice("Studio Laptop") == "Pinged Studio Laptop (192.168.1.31): 3 of 3 replies, average 5 ms.")
        #expect(pinger.hosts == ["192.168.1.31"])
        #expect(toolbox.record.deviceIDs == [laptop.id])
    }

    @Test func nothingIsPingedDuringAScan() async {
        let pinger = MockScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger, scanning: Live.Flag(true)))
        #expect(await toolbox.pingDevice("dev-b") == AskToolbox.scanRunning)
        #expect(await toolbox.networkStatus() == AskToolbox.scanRunning)
        #expect(pinger.hosts.isEmpty)
        #expect(toolbox.record.measurements.map(\.text) == [
            "Synology DS920 (192.168.1.20): not pinged, a device scan is running", "Connection: not checked, a device scan is running"
        ])
    }

    /// Every outcome is kept for the question: a repeat neither pings nor refuses again, and the
    /// app shows one line per device.
    @Test func aRepeatedCallGivesTheSameResultAndOneLine() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([2, 2, 2])])
        let toolbox = Live.toolbox(Live.live(pinger))
        let first = await toolbox.pingDevice("dev-b")
        #expect(await toolbox.pingDevice("Synology DS920") == first)
        #expect(pinger.hosts == ["192.168.1.20"])

        let refused = Live.toolbox(Live.live(pinger))
        let offline = await refused.pingDevice("dev-a")
        #expect(await refused.pingDevice("dev-a") == offline)
        let timedOut = Live.toolbox(Live.live(MockScriptedPinger(["192.168.1.20": .hang]), deadline: .milliseconds(50)))
        let late = await timedOut.pingDevice("dev-b")
        #expect(await timedOut.pingDevice("dev-b") == late)
        for box in [toolbox, refused, timedOut] {
            #expect(box.record.measurements.count == 1)
            #expect(Set(box.record.measurements.map(\.id)).count == box.record.measurements.count)
        }
    }

    @Test func anAmbiguousDeviceIsListedNotPinged() async {
        let pinger = MockScriptedPinger([:])
        let output = await Live.toolbox(Live.live(pinger)).pingDevice("Apple")
        #expect(output.hasPrefix("3 devices match \"Apple\"; call again with one id:"))
        #expect(pinger.hosts.isEmpty)
    }

    @Test func liveToolsCountAgainstTheSoftCap() async {
        let pinger = MockScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger))
        for _ in 0 ..< AskToolbox.softCap {
            _ = toolbox.findDevices("NAS")
        }
        #expect(await toolbox.pingDevice("dev-b") == AskToolbox.limitMessage)
        #expect(await toolbox.networkStatus() == AskToolbox.limitMessage)
        #expect(pinger.hosts.isEmpty)
        #expect(toolbox.record.calls == AskToolbox.softCap + 2)
    }

    @Test func aLiveCallLimitStopsFurtherLiveCalls() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([2, 2, 2]), "192.168.1.88": .times([3, 3, 3])])
        let toolbox = Live.toolbox(Live.live(pinger).limited(to: 1))
        _ = await toolbox.pingDevice("dev-b")
        #expect(await toolbox.pingDevice("dev-c") == AskToolbox.liveLimitMessage)
        #expect(pinger.hosts == ["192.168.1.20"])
    }

    @Test func withoutLiveServicesTheToolsSaySo() async {
        let toolbox = Live.toolbox(nil)
        #expect(!toolbox.hasLiveTools)
        #expect(await toolbox.pingDevice("dev-b") == AskToolbox.liveUnavailable)
        #expect(await toolbox.networkStatus() == AskToolbox.liveUnavailable)
    }

    // MARK: - networkStatus

    @Test func networkStatusPingsTheGatewayAndAPublicAddress() async {
        let pinger = MockScriptedPinger(["192.168.1.1": .times([2, 2, 2]), AskLiveTools.internetHost: .times([15, 14, nil])])
        let toolbox = Live.toolbox(Live.live(pinger))
        let output = await toolbox.networkStatus()
        #expect(output == "Connection: Wi-Fi. Gateway at 192.168.1.1: 3 of 3 replies, average 2 ms. "
            + "Internet (pinged the public address 8.8.8.8): 2 of 3 replies, average 15 ms.")
        #expect(Set(pinger.hosts) == ["192.168.1.1", "8.8.8.8"])
        #expect(toolbox.record.measurements == [AskMeasurement(
            deviceID: nil, text: "Wi-Fi · gateway: 3 of 3 replies, 2 ms average · internet (8.8.8.8): 2 of 3 replies, 15 ms average",
            measuredAt: Live.measuredAt
        )])
        #expect(await toolbox.networkStatus() == output)
        #expect(pinger.hosts.count == 2)
    }

    @Test func networkStatusWithoutAConnectionPingsNothing() async {
        let pinger = MockScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger, connection: .init(type: nil, gatewayIP: nil)))
        #expect(await toolbox.networkStatus() == "No network connection. Nothing was pinged.")
        #expect(pinger.hosts.isEmpty)
    }

    /// A connected path of no recognised interface type (a tunnel) is `.none`, not disconnected
    /// (#627 review): only a nil type is no connection.
    @Test func networkStatusOnAConnectionOfUnknownTypeStillPingsTheInternet() async {
        let pinger = MockScriptedPinger([AskLiveTools.internetHost: .times([20, 20, 20])])
        let toolbox = Live.toolbox(Live.live(pinger, connection: .init(type: ConnectionType.none, gatewayIP: nil)))
        #expect(await toolbox.networkStatus() == "Connection: Connected. Gateway: not found, so not pinged. "
            + "Internet (pinged the public address 8.8.8.8): 3 of 3 replies, average 20 ms.")
        #expect(pinger.hosts == [AskLiveTools.internetHost])
        #expect(toolbox.record.measurements.map(\.text) == ["Connected · gateway: not found · internet (8.8.8.8): 3 of 3 replies, 20 ms average"])
    }

    @Test func networkStatusWithoutAGatewayStillPingsTheInternet() async {
        let pinger = MockScriptedPinger([AskLiveTools.internetHost: .times([20, 20, 20])])
        let toolbox = Live.toolbox(Live.live(pinger, connection: .init(type: .cellular, gatewayIP: nil)))
        #expect(await toolbox.networkStatus() == "Connection: Cellular. Gateway: not found, so not pinged. "
            + "Internet (pinged the public address 8.8.8.8): 3 of 3 replies, average 20 ms.")
    }

    @Test func networkStatusStopsAtTheDeadline() async {
        let pinger = MockScriptedPinger(["192.168.1.1": .hang, AskLiveTools.internetHost: .hang])
        let clock = ContinuousClock()
        let start = clock.now
        let output = await Live.toolbox(Live.live(pinger, deadline: .milliseconds(100))).networkStatus()
        #expect(clock.now - start < .seconds(2))
        #expect(output.contains("Gateway at 192.168.1.1: not measured, the ping didn't finish in time."))
    }
}

/// A question through the pipeline with the live tools (#579), with a scripted model.
@Suite("AskNetwork live tools")
struct AskNetworkLiveTests {
    typealias Fix = AskFixture
    typealias Live = AskLiveFixture

    private func ask(_ calls: [AskToolCall], answer: String, pinger: MockScriptedPinger) async -> AskAnswer {
        let question = "Is the NAS answering right now?"
        let model = ScriptedAskModel(scripts: [question: AskScript(calls: calls, answer: answer)])
        return await AskNetwork.answer(question, snapshot: Live.snapshot, pinnedDeviceID: nil, model: model, live: Live.live(pinger))
    }

    /// Verification of #627 (lead decision): word lists leaked, so once the model calls a live tool,
    /// whatever its outcome, no model sentence is shown; the app's lines are the answer.
    @Test(arguments: ["It works.", "It passed.", "It is doing great.", "Nothing came through.", "All three got through.",
                      "It took three milliseconds."])
    func noModelTextIsShownAfterALiveTool(_ sentence: String) async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let answer = await ask([.pingDevice("dev-b")], answer: sentence + " It is a storage device.", pinger: pinger)
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.measuredFallback)
        #expect(answer.measurements.count == 1)
    }

    @Test func aLiveCallPastTheSoftCapStillDropsTheModelsText() async {
        let calls = Array(repeating: AskToolCall.findDevices("NAS"), count: AskToolbox.softCap) + [.pingDevice("dev-b")]
        let answer = await ask(calls, answer: "It works.", pinger: MockScriptedPinger([:]))
        #expect(answer.text == nil)
        #expect(answer.measurements.isEmpty)
    }

    @Test func aRefusedLiveCallStillDropsTheModelsText() async {
        let pinger = MockScriptedPinger([:])
        let question = "Is the printer up?"
        let model = ScriptedAskModel(scripts: [question: AskScript(calls: [.pingDevice("dev-a")], answer: "It is a printer.")])
        let answer = await AskNetwork.answer(question, snapshot: Live.snapshot, pinnedDeviceID: nil, model: model, live: Live.live(pinger))
        #expect(answer.text == nil)
        #expect(answer.measurements.first?.measuredAt == nil)
    }

    /// With no live tool called, the model may not claim a check it didn't run.
    @Test func aClaimedPingWithoutALiveToolIsDropped() async {
        let question = "Is the NAS up?"
        let model = ScriptedAskModel(scripts: [question: AskScript(
            calls: [.findDevices("NAS")], answer: "It pinged fine. Synology DS920 is a storage device."
        )])
        let answer = await AskNetwork.answer(
            question, snapshot: Live.snapshot, pinnedDeviceID: nil, model: model, live: Live.live(MockScriptedPinger([:]))
        )
        #expect(answer.text == "Synology DS920 is a storage device.")
    }

    @Test func theModelsPresenceSentenceGoesAndTheAppsMeasurementShows() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let answer = await ask([.findDevices("NAS"), .pingDevice("dev-b")],
                               answer: "Yes, Synology DS920 is answering right now. It is a storage device.", pinger: pinger)
        #expect(answer.text == nil)
        #expect(answer.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): 3 of 3 replies, 4 ms average"])
        #expect(answer.devices.map(\.id) == [Fix.nas.id])
    }

    @Test func aNoReplyPingWithAModelSayingItPingedFineShowsOnlyTheApp() async {
        let answer = await ask([.pingDevice("dev-b")], answer: "It pinged fine.", pinger: MockScriptedPinger([:]))
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.measuredFallback)
        #expect(answer.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): no reply to 3 pings"])
    }

    @Test func aModelSentenceRestatingThePingIsDropped() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let answer = await ask([.pingDevice("dev-b")], answer: "Synology DS920 replied to 3 of 3 pings, average 4 ms.", pinger: pinger)
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.measuredFallback)
        #expect(answer.measurements.count == 1)
    }

    /// Real model, 2026-11-26: "… did not reply to 3 pings." for "Can you ping the printer?".
    @Test func aSentenceSayingNothingRepliedIsDropped() async {
        let answer = await ask([.pingDevice("dev-b")], answer: "Synology DS920 did not reply. It is a storage device.",
                               pinger: MockScriptedPinger([:]))
        #expect(answer.text == nil)
    }

    /// Real model, 2026-11-26: "The gateway at 192.168.1.1 responded in 2 ms" for "Why is the
    /// internet slow tonight?".
    @Test func aSentenceSayingSomethingRespondedIsDropped() async {
        let pinger = MockScriptedPinger(["192.168.1.1": .times([2, 2, 2]), AskLiveTools.internetHost: .times([15, 15, 15])])
        let question = "Why is the internet slow tonight?"
        let model = ScriptedAskModel(scripts: [question: AskScript(
            calls: [.networkStatus], answer: "The gateway responded quickly. The connection is Wi-Fi."
        )])
        let answer = await AskNetwork.answer(question, snapshot: Live.snapshot, pinnedDeviceID: nil, model: model, live: Live.live(pinger))
        #expect(answer.text == nil)
    }

    /// The model's sentences through the pipeline for each refusal: only the app's line says it.
    @Test func refusalsReachTheAnswerAsTheAppsLine() async {
        let away = Fix.device("Cabin Camera", .camera, ip: "10.0.0.8")
        let snapshot = AskSnapshot(devices: Fix.devices + [away], events: [], networkProfileID: Live.network.id, lastScan: Fix.now,
                                   now: Fix.now, calendar: Fix.calendar)
        let question = "Is it answering?"
        func answer(_ id: String, live: AskLiveTools) async -> AskAnswer {
            let model = ScriptedAskModel(scripts: [question: AskScript(calls: [.pingDevice(id)], answer: "It is a device.")])
            return await AskNetwork.answer(question, snapshot: snapshot, pinnedDeviceID: nil, model: model, live: live)
        }
        let offNetwork = await answer("Cabin Camera", live: Live.live(MockScriptedPinger([:])))
        #expect(offNetwork.measurements.map(\.text) == ["Cabin Camera (10.0.0.8): not pinged, not on the network this device is on now"])
        let scanning = await answer("dev-b", live: Live.live(MockScriptedPinger([:]), scanning: Live.Flag(true)))
        #expect(scanning.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): not pinged, a device scan is running"])
        let timedOut = await answer("dev-b", live: Live.live(MockScriptedPinger(["192.168.1.20": .hang]), deadline: .milliseconds(100)))
        #expect(timedOut.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): not measured, timed out"])
        let moved = await answer("dev-b", live: Live.live(MockScriptedPinger([:]), established: nil))
        #expect(moved.measurements.first?.text.hasSuffix(AskToolbox.scanFirst) == true)
        for result in [offNetwork, scanning, timedOut, moved] {
            #expect(result.text == nil)
        }
    }

    /// A live result never changes the saved status: a silent ping of a device the scan saw
    /// Online leaves its status Online and shows the app's no-reply line beside it.
    @Test func aLiveResultDoesNotChangeTheSavedStatus() async {
        let model = ScriptedAskModel(scripts: ["Q": AskScript(calls: [.pingDevice("dev-b")], answer: "It is a storage device.")])
        let answer = await AskNetwork.answer("Q", snapshot: Live.snapshot, pinnedDeviceID: nil, model: model,
                                             live: Live.live(MockScriptedPinger([:])))
        #expect(answer.devices.map(\.presence) == [.online])
        #expect(answer.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): no reply to 3 pings"])
        #expect(Fix.nas.status == .online)
    }

    @Test func theHardStopStillEndsATurnOfLiveCalls() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let calls = Array(repeating: AskToolCall.pingDevice("dev-b"), count: AskToolbox.hardStop + 1)
        let answer = await ask(calls, answer: "It is a storage device.", pinger: pinger)
        #expect(answer.text == nil)
        #expect(pinger.hosts == ["192.168.1.20"])
    }

    @Test func theInstructionsOfferTheLiveToolsOnlyWithThem() {
        #expect(AskNetwork.instructions(for: Live.snapshot, live: true).contains("pingDevice"))
        #expect(!AskNetwork.instructions(for: Live.snapshot).contains("pingDevice"))
        #expect(AskNetwork.instructions(for: Live.snapshot).contains("The tools don't measure the internet connection."))
    }

    @Test func aCancelledQuestionMeasuresNothingMore() async {
        let pinger = MockScriptedPinger(["192.168.1.20": .hang])
        let question = "Is the NAS answering right now?"
        let model = ScriptedAskModel(scripts: [question: AskScript(calls: [.pingDevice("dev-b"), .networkStatus], answer: "No.")])
        let task = Task {
            await AskNetwork.answer(question, snapshot: Live.snapshot, pinnedDeviceID: nil, model: model,
                                    live: Live.live(pinger, deadline: .seconds(60)))
        }
        await waitUntil { !pinger.hosts.isEmpty }
        task.cancel()
        let answer = await task.value
        #expect(answer.text == nil)
        #expect(answer.measurements.isEmpty)
        // The follow-up connection check started no probe.
        #expect(pinger.hosts == ["192.168.1.20"])
    }
}

@Suite("NetworkJoinClock")
@MainActor
struct NetworkJoinClockTests {
    final class Clock: Sendable {
        private let value = Mutex(Date(timeIntervalSince1970: 0))
        func advance() { value.withLock { $0 = $0.addingTimeInterval(60) } }
        var now: Date { value.withLock { $0 } }
    }

    /// `waitUntil` on the main actor, which the clock is isolated to.
    private func waitFor(_ date: Date, on join: NetworkJoinClock) async {
        let deadline = ContinuousClock.now + .seconds(5)
        while join.joinedAt != date, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func aNewPathIsANewJoinAndTheSamePathIsNot() async {
        let (changes, continuation) = AsyncStream<String>.makeStream()
        let clock = Clock()
        let join = NetworkJoinClock(changes: changes) { clock.now }
        #expect(join.joinedAt == Date(timeIntervalSince1970: 0))
        clock.advance()
        continuation.yield("satisfied|wifi-en0|192.168.1.1")
        await waitFor(Date(timeIntervalSince1970: 60), on: join)
        #expect(join.joinedAt == Date(timeIntervalSince1970: 60))
        clock.advance()
        continuation.yield("satisfied|wifi-en0|192.168.1.1")
        try? await Task.sleep(for: .milliseconds(50))
        #expect(join.joinedAt == Date(timeIntervalSince1970: 60))
        // A same-subnet move passes through another path on the way.
        continuation.yield("unsatisfied")
        await waitFor(Date(timeIntervalSince1970: 120), on: join)
        #expect(join.joinedAt == Date(timeIntervalSince1970: 120))
    }

    /// Verification of #627: a same-subnet IPv4-only LAN gives the same path key, so coming back
    /// from the background is a possible join.
    @Test func aResumeIsAPossibleJoin() {
        let (changes, _) = AsyncStream<String>.makeStream()
        let clock = Clock()
        let join = NetworkJoinClock(changes: changes) { clock.now }
        let start = join.scanStarted()
        join.scanReconciled(joinedAtStart: start, at: Date(timeIntervalSince1970: 30))
        #expect(join.establishedAt == Date(timeIntervalSince1970: 30))
        clock.advance()
        join.noteResume()
        #expect(join.joinedAt == Date(timeIntervalSince1970: 60))
        #expect(join.establishedAt == nil)
    }

    /// Verification of #627: a scan that spans a move (A to B) doesn't establish B.
    @Test func aScanThatSpansAMoveDoesNotEstablishTheNetwork() async {
        let (changes, continuation) = AsyncStream<String>.makeStream()
        let clock = Clock()
        let join = NetworkJoinClock(changes: changes) { clock.now }
        let start = join.scanStarted()
        clock.advance()
        continuation.yield("satisfied|wifi-en0|network-b")
        await waitFor(Date(timeIntervalSince1970: 60), on: join)
        join.scanReconciled(joinedAtStart: start, at: Date(timeIntervalSince1970: 90))
        #expect(join.establishedAt == nil)
        // The next scan, all on B, does.
        let next = join.scanStarted()
        join.scanReconciled(joinedAtStart: next, at: Date(timeIntervalSince1970: 150))
        #expect(join.establishedAt == Date(timeIntervalSince1970: 150))
    }
}

/// Verification of #627: the network the snapshot is asked about (iOS: the saved local profile)
/// and the one the live tools check against (`currentProfile`) are the same profile ID.
@Suite("Ask network ID sources")
@MainActor
struct AskNetworkIDSourceTests {
    @Test func theSavedLocalProfileAndTheCurrentProfileAgree() throws {
        let defaults = try #require(UserDefaults(suiteName: "ask-network-id-\(UUID().uuidString)"))
        let live = NetworkProfile(
            interfaceName: "en0", ipAddress: "192.168.1.10", network: AskLiveFixture.network.network, connectionType: .wifi
        )
        let manager = NetworkProfileManager(userDefaults: defaults, activeProfilesProvider: { [live] })
        _ = manager
        let saved = try #require(NetworkProfileManager.savedLocalProfile(in: defaults))
        let current = NetworkProfileManager.currentProfile(active: { [live] }, saved: { NetworkProfileManager.savedLocalProfile(in: defaults) })
        #expect(current?.id == saved.id)
        // Off that network: no current profile, so nothing is pinged.
        #expect(NetworkProfileManager.currentProfile(active: { [] }, saved: { saved }) == nil)
    }
}
