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

/// Waits until `condition` holds, at most `timeout`.
private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

/// The fixture network as the live tools see it (#579): 192.168.1.0/24, which the phone is on,
/// joined an hour before the scan at `Fix.now`.
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
    /// Joined the network an hour before the last scan.
    static let joined = Fix.now.addingTimeInterval(-3600)

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
        joined: Date? = joined,
        deadline: Duration = .seconds(5)
    ) -> AskLiveTools {
        AskLiveTools(
            pinger: pinger, currentNetwork: { network }, connection: { connection }, isScanning: { scanning.isSet },
            joinedAt: { joined }, now: { measuredAt }, deadline: deadline
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
        #expect(output == "Pinged Synology DS920 (192.168.1.20): 3 of 3 replies, average 4 ms.")
        #expect(pinger.hosts == ["192.168.1.20"])
        #expect(toolbox.record.deviceIDs == [Fix.nas.id])
        #expect(toolbox.record.measurements == [AskMeasurement(
            deviceID: Fix.nas.id, text: "Synology DS920 (192.168.1.20): 3 of 3 replies, 4 ms average", measuredAt: Live.measuredAt
        )])
    }

    @Test func lostProbesCountAgainstTheThreeSent() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([2, nil, 4])])
        let output = await Live.toolbox(Live.live(pinger)).pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 (192.168.1.20): 2 of 3 replies, average 3 ms.")
    }

    @Test func noReplyIsNeverCalledOfflineAndSaysTheScanDisagreed() async {
        let toolbox = Live.toolbox(Live.live(ScriptedPinger([:])))
        let output = await toolbox.pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 (192.168.1.20): no reply to 3 pings.")
        #expect(toolbox.record.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): no reply to 3 pings"])
        #expect(toolbox.record.measurements.first?.lastScanNote == "At the last scan less than a minute ago it was online.")
    }

    @Test func aPingThatOutlivesTheDeadlineIsNotMeasured() async {
        let pinger = ScriptedPinger(["192.168.1.20": .hang])
        let toolbox = Live.toolbox(Live.live(pinger, deadline: .milliseconds(100)))
        let output = await toolbox.pingDevice("dev-b")
        #expect(output == "Pinged Synology DS920 (192.168.1.20): not measured, the ping didn't finish in time.")
        #expect(toolbox.record.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): not measured, timed out"])
    }

    @Test func aCancelledPingReturnsWithoutAMeasurement() async {
        let pinger = ScriptedPinger(["192.168.1.20": .hang])
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
        let pinger = ScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger), snapshot: snapshot)
        let output = await toolbox.pingDevice("dev-a")
        #expect(output == "Cabin Camera was not pinged: its address is not on the network this device is on now.")
        #expect(pinger.hosts.isEmpty)
        #expect(toolbox.record.measurements == [AskMeasurement(
            deviceID: away.id, text: "Cabin Camera (10.0.0.8): not pinged, not on the network this device is on now", measuredAt: nil
        )])
    }

    @Test func nothingIsPingedOffTheNetworkAskedAbout() async {
        let pinger = ScriptedPinger([:])
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
        let pinger = ScriptedPinger(["192.168.1.20": .times([2, 2, 2])])
        let movedAfterTheScan = Live.toolbox(Live.live(pinger, joined: Fix.now.addingTimeInterval(60)))
        let output = await movedAfterTheScan.pingDevice("dev-b")
        #expect(output == "Run a scan first: this network hasn't been checked since you joined it. Synology DS920 was not pinged.")
        #expect(movedAfterTheScan.record.measurements.map(\.text)
            == ["Synology DS920 (192.168.1.20): not pinged. Run a scan first: this network hasn't been checked since you joined it."])
        #expect(movedAfterTheScan.record.measurements.first?.measuredAt == nil)
        #expect(pinger.hosts.isEmpty)

        let unknownJoin = await Live.toolbox(Live.live(pinger, joined: nil)).pingDevice("dev-b")
        #expect(unknownJoin.hasPrefix(AskToolbox.scanFirst))
        let neverScanned = AskSnapshot(devices: Fix.devices, events: [], networkProfileID: Live.network.id, lastScan: nil, now: Fix.now,
                                       calendar: Fix.calendar)
        #expect(await Live.toolbox(Live.live(pinger), snapshot: neverScanned).pingDevice("dev-b").hasPrefix(AskToolbox.scanFirst))
        #expect(pinger.hosts.isEmpty)

        // A scan after the move establishes the network.
        let scannedSince = Live.toolbox(Live.live(pinger, joined: Fix.now.addingTimeInterval(-60)))
        #expect(await scannedSince.pingDevice("dev-b") == "Pinged Synology DS920 (192.168.1.20): 3 of 3 replies, average 2 ms.")
    }

    @Test func aDeviceOfflineAtTheScanIsNotPingedAtItsOldAddress() async {
        let pinger = ScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger))
        let output = await toolbox.pingDevice("dev-a")
        #expect(output == "Brother HL-L2350DW was not pinged: it didn't answer the last scan; it was last seen at this address 2 hours ago.")
        #expect(toolbox.record.measurements.map(\.text)
            == ["Brother HL-L2350DW (192.168.1.57): not pinged, last seen at this address 2 hours ago"])
        #expect(pinger.hosts.isEmpty)
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
        let pinger = ScriptedPinger(["192.168.1.31": .times([5, 5, 5])])
        let toolbox = Live.toolbox(Live.live(pinger), snapshot: snapshot)
        #expect(await toolbox.pingDevice("Studio Laptop") == "Pinged Studio Laptop (192.168.1.31): 3 of 3 replies, average 5 ms.")
        #expect(pinger.hosts == ["192.168.1.31"])
        #expect(toolbox.record.deviceIDs == [laptop.id])
    }

    @Test func nothingIsPingedDuringAScan() async {
        let pinger = ScriptedPinger([:])
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
        let pinger = ScriptedPinger(["192.168.1.20": .times([2, 2, 2])])
        let toolbox = Live.toolbox(Live.live(pinger))
        let first = await toolbox.pingDevice("dev-b")
        #expect(await toolbox.pingDevice("Synology DS920") == first)
        #expect(pinger.hosts == ["192.168.1.20"])

        let refused = Live.toolbox(Live.live(pinger))
        let offline = await refused.pingDevice("dev-a")
        #expect(await refused.pingDevice("dev-a") == offline)
        let timedOut = Live.toolbox(Live.live(ScriptedPinger(["192.168.1.20": .hang]), deadline: .milliseconds(50)))
        let late = await timedOut.pingDevice("dev-b")
        #expect(await timedOut.pingDevice("dev-b") == late)
        for box in [toolbox, refused, timedOut] {
            #expect(box.record.measurements.count == 1)
            #expect(Set(box.record.measurements.map(\.id)).count == box.record.measurements.count)
        }
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

    @Test func aLiveCallLimitStopsFurtherLiveCalls() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([2, 2, 2]), "192.168.1.88": .times([3, 3, 3])])
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
        let pinger = ScriptedPinger(["192.168.1.1": .times([2, 2, 2]), AskLiveTools.internetHost: .times([15, 14, nil])])
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
        let pinger = ScriptedPinger([:])
        let toolbox = Live.toolbox(Live.live(pinger, connection: .init(type: nil, gatewayIP: nil)))
        #expect(await toolbox.networkStatus() == "No network connection. Nothing was pinged.")
        #expect(pinger.hosts.isEmpty)
    }

    @Test func networkStatusWithoutAGatewayStillPingsTheInternet() async {
        let pinger = ScriptedPinger([AskLiveTools.internetHost: .times([20, 20, 20])])
        let toolbox = Live.toolbox(Live.live(pinger, connection: .init(type: .cellular, gatewayIP: nil)))
        #expect(await toolbox.networkStatus() == "Connection: Cellular. Gateway: not found, so not pinged. "
            + "Internet (pinged the public address 8.8.8.8): 3 of 3 replies, average 20 ms.")
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
                               answer: "Yes, Synology DS920 is answering right now. It is a storage device.", pinger: pinger)
        #expect(answer.text == "It is a storage device.")
        #expect(answer.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): 3 of 3 replies, 4 ms average"])
        #expect(answer.devices.map(\.id) == [Fix.nas.id])
    }

    /// Codex review of #627: paraphrases with no presence word still asserted the live result,
    /// and "3 ms" passed grounding because 3 is the probe count. Once a live tool ran, the app's
    /// line is the answer: no model sentence with a digit or the live vocabulary is shown.
    @Test(arguments: ["It pinged fine.", "The ping succeeded.", "It got a reply in 4 ms.", "Its average latency is 3 ms."])
    func aModelSentenceAboutTheLiveResultIsDropped(_ sentence: String) async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let answer = await ask([.pingDevice("dev-b")], answer: sentence + " It is a storage device.", pinger: pinger)
        // A name with digits ("DS920") goes too: after a live tool no digit is the model's.
        #expect(answer.text == "It is a storage device.")
        #expect(answer.measurements.count == 1)
    }

    @Test func aNoReplyPingWithAModelSayingItPingedFineShowsOnlyTheApp() async {
        let answer = await ask([.pingDevice("dev-b")], answer: "It pinged fine.", pinger: ScriptedPinger([:]))
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.measuredFallback)
        #expect(answer.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): no reply to 3 pings"])
    }

    @Test func aModelSentenceRestatingThePingIsDropped() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
        let answer = await ask([.pingDevice("dev-b")], answer: "Synology DS920 replied to 3 of 3 pings, average 4 ms.", pinger: pinger)
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.measuredFallback)
        #expect(answer.measurements.count == 1)
    }

    /// Real model, 2026-11-26: "… did not reply to 3 pings." for "Can you ping the printer?".
    @Test func aSentenceSayingNothingRepliedIsDropped() async {
        let answer = await ask([.pingDevice("dev-b")], answer: "Synology DS920 did not reply. It is a storage device.",
                               pinger: ScriptedPinger([:]))
        #expect(answer.text == "It is a storage device.")
    }

    /// Real model, 2026-11-26: "The gateway at 192.168.1.1 responded in 2 ms" for "Why is the
    /// internet slow tonight?".
    @Test func aSentenceSayingSomethingRespondedIsDropped() async {
        let pinger = ScriptedPinger(["192.168.1.1": .times([2, 2, 2]), AskLiveTools.internetHost: .times([15, 15, 15])])
        let question = "Why is the internet slow tonight?"
        let model = ScriptedAskModel(scripts: [question: AskScript(
            calls: [.networkStatus], answer: "The gateway responded quickly. The connection is Wi-Fi."
        )])
        let answer = await AskNetwork.answer(question, snapshot: Live.snapshot, pinnedDeviceID: nil, model: model, live: Live.live(pinger))
        #expect(answer.text == "The connection is Wi-Fi.")
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
        let offNetwork = await answer("Cabin Camera", live: Live.live(ScriptedPinger([:])))
        #expect(offNetwork.measurements.map(\.text) == ["Cabin Camera (10.0.0.8): not pinged, not on the network this device is on now"])
        let scanning = await answer("dev-b", live: Live.live(ScriptedPinger([:]), scanning: Live.Flag(true)))
        #expect(scanning.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): not pinged, a device scan is running"])
        let timedOut = await answer("dev-b", live: Live.live(ScriptedPinger(["192.168.1.20": .hang]), deadline: .milliseconds(100)))
        #expect(timedOut.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): not measured, timed out"])
        let moved = await answer("dev-b", live: Live.live(ScriptedPinger([:]), joined: Fix.now.addingTimeInterval(60)))
        #expect(moved.measurements.first?.text.hasSuffix(AskToolbox.scanFirst) == true)
        for result in [offNetwork, scanning, timedOut, moved] {
            #expect(result.text == "It is a device.")
        }
    }

    @Test func aLiveReplyDoesNotChangeTheSavedStatus() async {
        // The last scan is 50 minutes old, so the NAS's status reads "not checked recently"; a
        // reply now is shown as a measurement only.
        let stale = AskSnapshot(devices: Fix.devices, events: [], networkProfileID: Live.network.id,
                                lastScan: Fix.now.addingTimeInterval(-3000), now: Fix.now, calendar: Fix.calendar)
        let model = ScriptedAskModel(scripts: ["Q": AskScript(calls: [.pingDevice("dev-b")], answer: "It is a storage device.")])
        let answer = await AskNetwork.answer("Q", snapshot: stale, pinnedDeviceID: nil, model: model,
                                             live: Live.live(ScriptedPinger(["192.168.1.20": .times([6, 6, 6])])))
        #expect(answer.devices.map(\.presence) == [.notCheckedRecently])
        #expect(answer.measurements.map(\.text) == ["Synology DS920 (192.168.1.20): 3 of 3 replies, 6 ms average"])
        #expect(Fix.nas.status == .online)
    }

    @Test func theHardStopStillEndsATurnOfLiveCalls() async {
        let pinger = ScriptedPinger(["192.168.1.20": .times([4, 4, 4])])
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
        let pinger = ScriptedPinger(["192.168.1.20": .hang])
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
}
