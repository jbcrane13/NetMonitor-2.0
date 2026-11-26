import Testing
import Foundation
import Synchronization
@testable import NetMonitorCore

/// A pinger that answers each host as scripted (#579): reply times (nil for a lost probe), or no
/// answer at all until it is cancelled.
final class ScriptedPinger: PingServiceProtocol, Sendable {
    enum Reply: Sendable {
        case times([Double?])
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
        case .hang:
            return AsyncStream { _ in }
        }
    }

    func stop() async {}

    func calculateStatistics(_ results: [PingResult], requestedCount: Int?) async -> PingStatistics? { nil }
}

/// The fixture network as the live tools see it (#579): 192.168.1.0/24, which the phone is on.
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

    final class Flag: Sendable {
        private let value: Mutex<Bool>
        init(_ value: Bool = false) { self.value = Mutex(value) }
        func set(_ new: Bool) { value.withLock { $0 = new } }
        var isSet: Bool { value.withLock { $0 } }
    }

    static func live(
        _ pinger: ScriptedPinger,
        network: NetworkProfile? = network,
        connection: AskLiveTools.Connection = .init(type: .wifi, gatewayIP: "192.168.1.1"),
        scanning: Flag = Flag(),
        deadline: Duration = .seconds(5)
    ) -> AskLiveTools {
        AskLiveTools(
            pinger: pinger, currentNetwork: { network }, connection: { connection }, isScanning: { scanning.isSet },
            now: { measuredAt }, deadline: deadline
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
        let pinger = ScriptedPinger(["192.168.1.20": .times([3.6, 4.2, 4.2])])
        let toolbox = Live.toolbox(Live.live(pinger))
        let output = await toolbox.pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 at 192.168.1.20: 3 of 3 replies, average 4 ms.")
        #expect(pinger.hosts == ["192.168.1.20"])
        #expect(toolbox.record.deviceIDs == [Fix.nas.id])
        #expect(toolbox.record.measurements == [
            AskMeasurement(deviceID: Fix.nas.id, text: "Synology DS920: 3 of 3 replies, 4 ms average", measuredAt: Live.measuredAt)
        ])
    }

    @Test func lostProbesCountAgainstTheThreeSent() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([2, nil, 4])])
        let output = await Live.toolbox(Live.live(pinger)).pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 at 192.168.1.20: 2 of 3 replies, average 3 ms.")
    }

    @Test func noReplyIsNeverCalledOffline() async {
        let toolbox = Live.toolbox(Live.live(ScriptedPinger([:])))
        let output = await toolbox.pingDevice("dev-a")
        #expect(output == "Pinged Brother HL-L2350DW at 192.168.1.57: no reply to 3 pings.")
        #expect(toolbox.record.measurements.map(\.text) == ["Brother HL-L2350DW: no reply to 3 pings"])
    }

    @Test func aPingThatOutlivesTheDeadlineIsNotMeasured() async {
        let pinger = ScriptedPinger(["192.168.1.20": .hang])
        let toolbox = Live.toolbox(Live.live(pinger, deadline: .milliseconds(100)))
        let output = await toolbox.pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 at 192.168.1.20: not measured, the ping didn't finish in time.")
        #expect(toolbox.record.measurements.map(\.text) == ["Synology DS920: not measured, timed out"])
    }

    @Test func aCancelledPingReturnsWithoutAMeasurement() async {
        let pinger = ScriptedPinger(["192.168.1.20": .hang])
        let toolbox = Live.toolbox(Live.live(pinger, deadline: .seconds(60)))
        let task = Task { await toolbox.pingDevice("dev-b") }
        while pinger.hosts.isEmpty {
            await Task.yield()
        }
        task.cancel()
        let output = await task.value
        #expect(output.hasSuffix("not measured, cancelled."))
        #expect(toolbox.record.measurements.isEmpty)
    }

    @Test func aDeviceOutsideTheCurrentNetworkIsNotPinged() async {
        let away = Fix.device("Cabin Camera", .camera, ip: "10.0.0.8")
        let snapshot = AskSnapshot(devices: [away], events: [], networkProfileID: Live.network.id, lastScan: Fix.now, now: Fix.now,
                                   calendar: Fix.calendar)
        let pinger = ScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger), snapshot: snapshot)
        let output = await toolbox.pingDevice("dev-a")
        #expect(output == "Cabin Camera was not pinged: its address 10.0.0.8 is not on the network this device is on now.")
        #expect(pinger.hosts.isEmpty)
        #expect(toolbox.record.measurements.map(\.text) == ["Cabin Camera: not pinged, not on the network this device is on now"])
    }

    @Test func nothingIsPingedOffTheNetworkAskedAbout() async {
        let pinger = ScriptedPinger([:])
        // Not connected, or on another saved network with the same subnet.
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

    @Test func nothingIsPingedDuringAScan() async {
        let pinger = ScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger, scanning: Live.Flag(true)))
        #expect(await toolbox.pingDevice("dev-b") == AskToolbox.scanRunning)
        #expect(await toolbox.networkStatus() == AskToolbox.scanRunning)
        #expect(pinger.hosts.isEmpty)
        #expect(toolbox.record.measurements.map(\.text) == [
            "Synology DS920: not pinged, a device scan is running", "Connection: not measured, a device scan is running"
        ])
    }

    @Test func aRepeatedPingIsNotMeasuredAgain() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([2, 2, 2])])
        let toolbox = Live.toolbox(Live.live(pinger))
        let first = await toolbox.pingDevice("dev-b")
        #expect(await toolbox.pingDevice("Synology DS920") == first)
        #expect(pinger.hosts == ["192.168.1.20"])
        #expect(toolbox.record.measurements.count == 1)
    }

    @Test func anAmbiguousDeviceIsListedNotPinged() async {
        let pinger = ScriptedPinger([:])
        let output = await Live.toolbox(Live.live(pinger)).pingDevice("Apple")
        #expect(output.hasPrefix("3 devices match \"Apple\"; call again with one id:"))
        #expect(pinger.hosts.isEmpty)
    }

    @Test func liveToolsCountAgainstTheSoftCap() async {
        let pinger = ScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger))
        for _ in 0 ..< AskToolbox.softCap {
            _ = toolbox.findDevices("NAS")
        }
        #expect(await toolbox.pingDevice("dev-b") == AskToolbox.limitMessage)
        #expect(await toolbox.networkStatus() == AskToolbox.limitMessage)
        #expect(pinger.hosts.isEmpty)
        #expect(toolbox.record.calls == AskToolbox.softCap + 2)
    }

    @Test func withoutLiveServicesTheToolsSaySo() async {
        let toolbox = Live.toolbox(nil)
        #expect(!toolbox.hasLiveTools)
        #expect(await toolbox.pingDevice("dev-b") == AskToolbox.liveUnavailable)
        #expect(await toolbox.networkStatus() == AskToolbox.liveUnavailable)
    }

    // MARK: - networkStatus

    @Test func networkStatusPingsTheGatewayAndTheInternet() async {
        let pinger = ScriptedPinger(["192.168.1.1": .times([2, 2, 2]), AskLiveTools.internetHost: .times([15, 14, nil])])
        let toolbox = Live.toolbox(Live.live(pinger))
        let output = await toolbox.networkStatus()
        #expect(output == "Connection: Wi-Fi. Gateway at 192.168.1.1: 3 of 3 replies, average 2 ms. "
            + "Internet (pinged 8.8.8.8): 2 of 3 replies, average 15 ms.")
        #expect(Set(pinger.hosts) == ["192.168.1.1", "8.8.8.8"])
        #expect(toolbox.record.measurements == [AskMeasurement(
            deviceID: nil, text: "Wi-Fi · gateway: 3 of 3 replies, 2 ms average · internet: 2 of 3 replies, 15 ms average",
            measuredAt: Live.measuredAt
        )])
        #expect(await toolbox.networkStatus() == output)
        #expect(pinger.hosts.count == 2)
    }

    @Test func networkStatusWithoutAConnectionPingsNothing() async {
        let pinger = ScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger, connection: .init(type: nil, gatewayIP: nil)))
        #expect(await toolbox.networkStatus() == "No network connection. Nothing was pinged.")
        #expect(pinger.hosts.isEmpty)
    }

    @Test func networkStatusWithoutAGatewayStillPingsTheInternet() async {
        let pinger = ScriptedPinger([AskLiveTools.internetHost: .times([20, 20, 20])])
        let toolbox = Live.toolbox(Live.live(pinger, connection: .init(type: .cellular, gatewayIP: nil)))
        #expect(await toolbox.networkStatus()
            == "Connection: Cellular. Gateway: not found, so not pinged. Internet (pinged 8.8.8.8): 3 of 3 replies, average 20 ms.")
    }

    @Test func networkStatusStopsAtTheDeadline() async {
        let pinger = ScriptedPinger(["192.168.1.1": .hang, AskLiveTools.internetHost: .hang])
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

    private func ask(_ calls: [AskToolCall], answer: String, pinger: ScriptedPinger) async -> AskAnswer {
        let question = "Is the NAS answering right now?"
        let model = ScriptedAskModel(scripts: [question: AskScript(calls: calls, answer: answer)])
        return await AskNetwork.answer(question, snapshot: Live.snapshot, pinnedDeviceID: nil, model: model, live: Live.live(pinger))
    }

    @Test func theModelsPresenceSentenceGoesAndTheAppsMeasurementShows() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let answer = await ask([.findDevices("NAS"), .pingDevice("dev-b")],
                               answer: "Yes, Synology DS920 is answering right now. Its address is 192.168.1.20.", pinger: pinger)
        #expect(answer.text == "Its address is 192.168.1.20.")
        #expect(answer.measurements.map(\.text) == ["Synology DS920: 3 of 3 replies, 4 ms average"])
        #expect(answer.devices.map(\.id) == [Fix.nas.id])
    }

    @Test func aModelSentenceRestatingThePingIsDropped() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let answer = await ask([.pingDevice("dev-b")], answer: "Synology DS920 replied to 3 of 3 pings, average 4 ms.", pinger: pinger)
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.measuredFallback)
        #expect(answer.measurements.count == 1)
    }

    @Test func aLiveReplyDoesNotChangeTheSavedStatus() async {
        // The printer is offline as of the scan; a reply now is shown as a measurement only.
        let pinger = ScriptedPinger(["192.168.1.57": .times([6, 6, 6])])
        let answer = await ask([.pingDevice("dev-a")], answer: "Brother HL-L2350DW is a printer.", pinger: pinger)
        #expect(answer.devices.map(\.presence) == [.offline])
        #expect(answer.measurements.map(\.text) == ["Brother HL-L2350DW: 3 of 3 replies, 6 ms average"])
        #expect(Fix.printer.status == .offline)
    }

    @Test func aNumberTheMeasurementDidNotGiveIsRejected() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let answer = await ask([.pingDevice("dev-b")], answer: "Synology DS920 took 9 ms on average.", pinger: pinger)
        #expect(answer.text == nil)
        #expect(answer.measurements.count == 1)
    }

    @Test func theHardStopStillEndsATurnOfLiveCalls() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let calls = Array(repeating: AskToolCall.pingDevice("dev-b"), count: AskToolbox.hardStop + 1)
        let answer = await ask(calls, answer: "Its address is 192.168.1.20.", pinger: pinger)
        #expect(answer.text == nil)
        #expect(pinger.hosts == ["192.168.1.20"])
    }

    @Test func theInstructionsOfferTheLiveToolsOnlyWithThem() {
        #expect(AskNetwork.instructions(for: Live.snapshot, live: true).contains("pingDevice"))
        #expect(!AskNetwork.instructions(for: Live.snapshot).contains("pingDevice"))
        #expect(AskNetwork.instructions(for: Live.snapshot).contains("The tools don't measure the internet connection."))
    }

    @Test func aCancelledQuestionMeasuresNothingMore() async {
        let pinger = ScriptedPinger(["192.168.1.20": .hang])
        let question = "Is the NAS answering right now?"
        let model = ScriptedAskModel(scripts: [question: AskScript(calls: [.pingDevice("dev-b"), .networkStatus], answer: "No.")])
        let task = Task {
            await AskNetwork.answer(question, snapshot: Live.snapshot, pinnedDeviceID: nil, model: model,
                                    live: Live.live(pinger, deadline: .seconds(60)))
        }
        while pinger.hosts.isEmpty {
            await Task.yield()
        }
        task.cancel()
        let answer = await task.value
        #expect(answer.text == nil)
        #expect(answer.measurements.isEmpty)
    }
}
