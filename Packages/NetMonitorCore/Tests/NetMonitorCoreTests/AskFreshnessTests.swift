import Testing
import Foundation
@testable import NetMonitorCore

/// How fresh Ask's presence answers are (#452, after #589): the app works out "as of the scan N
/// minutes ago" or "not checked recently" from the network's last scan, and an old status never
/// reads as online now (Blake, 2026-11-24).
@Suite("AskFreshness")
struct AskFreshnessTests {
    typealias Fix = AskFixture

    /// The 40-minute case from the brief: the NAS answered the network's last scan, 40 minutes ago.
    private static let fortyMinutesAgo = Fix.now.addingTimeInterval(-40 * 60)
    private static let staleNAS = Fix.device("Synology DS920", .storage, ip: "192.168.1.20", lastSeen: fortyMinutesAgo, latency: 2)
    private static let stale = AskSnapshot(
        devices: [staleNAS], events: [], lastScan: fortyMinutesAgo, now: Fix.now, calendar: Fix.calendar
    )

    private func ask(_ question: String, calls: [AskToolCall], answer: String, snapshot: AskSnapshot) async -> AskAnswer {
        let model = ScriptedAskModel(scripts: [question: AskScript(calls: calls, answer: answer)])
        return await AskNetwork.answer(question, snapshot: snapshot, pinnedDeviceID: nil, model: model)
    }

    // MARK: - Snapshot

    @Test func relativeTimesUseOneUnit() {
        let snapshot = Fix.snapshot
        #expect(snapshot.ago(Fix.now.addingTimeInterval(-20)) == "less than a minute ago")
        #expect(snapshot.ago(Fix.now.addingTimeInterval(-60)) == "1 minute ago")
        #expect(snapshot.ago(Fix.now.addingTimeInterval(-40 * 60)) == "40 minutes ago")
        #expect(snapshot.ago(Fix.now.addingTimeInterval(-(2 * 3600 + 46 * 60))) == "2 hours ago")
        #expect(snapshot.ago(Fix.now.addingTimeInterval(-3 * 86400)) == "3 days ago")
        // A clock that moved backwards is not "in the future".
        #expect(snapshot.ago(Fix.now.addingTimeInterval(90)) == "less than a minute ago")
    }

    @Test func aScanWithinTheGraceIntervalIsFresh() {
        let snapshot = AskSnapshot(devices: [], events: [], lastScan: Fix.now.addingTimeInterval(-3 * 60), now: Fix.now, calendar: Fix.calendar)
        #expect(snapshot.scanFreshness == .fresh)
        #expect(snapshot.freshnessNote == "Device status as of the scan 3 minutes ago (2026-11-23 11:57 AM).")
    }

    @Test func aScanOlderThanTheGraceIntervalIsNotRecent() {
        #expect(Self.stale.staleAfter == DeviceGracePolicy().interval)
        #expect(Self.stale.scanFreshness == .stale)
        #expect(Self.stale.freshnessNote == "Not checked recently: the last scan was 40 minutes ago (2026-11-23 11:20 AM).")
    }

    @Test func aNetworkNeverScannedSaysSo() {
        let snapshot = AskSnapshot(devices: [Self.staleNAS], events: [], lastScan: nil, now: Fix.now, calendar: Fix.calendar)
        #expect(snapshot.scanFreshness == .notScanned)
        #expect(snapshot.freshnessNote == "This network hasn't been scanned yet, so no device's status has been checked.")
    }

    // MARK: - Tool text

    @Test func aStaleStatusNeverSaysOnline() {
        let toolbox = AskToolbox(snapshot: Self.stale)
        let status = toolbox.deviceStatus("the NAS")
        #expect(status == """
        Synology DS920 answered the last scan, 40 minutes ago (2026-11-23 11:20 AM); not checked recently. \
        Last seen 40 minutes ago (2026-11-23 11:20 AM). Address 192.168.1.20. Last reply 2 ms. \
        Went offline 0 times in the last 7 days (2026-11-17 to 2026-11-23).
        """)
        let list = toolbox.findDevices("all")
        #expect(list == """
        Not checked recently: the last scan was 40 minutes ago (2026-11-23 11:20 AM). Whether these devices are online now is not known.
        1 saved device:
        - id dev-a: Synology DS920, storage, answered the last scan, last seen 40 minutes ago (2026-11-23 11:20 AM), address 192.168.1.20
        """)
        // Only the note mentions "online", to say it isn't known.
        #expect(!status.lowercased().contains("online"))
        #expect(list.components(separatedBy: "\n").dropFirst().allSatisfy { !$0.lowercased().contains("online") })
    }

    @Test func aFreshScanSaysOnlineAsOfTheScan() {
        let status = Fix.toolbox().deviceStatus("the NAS")
        #expect(status.hasPrefix("Synology DS920 is online as of the scan less than a minute ago (2026-11-23 12:00 PM). "
            + "Last seen less than a minute ago (2026-11-23 12:00 PM)."))
    }

    @Test func aDeviceStillInGraceThatMissedTheLastScanIsNotOnline() {
        // iPhone rows stay .online through the grace interval after a missed scan (#582).
        let missed = Fix.device("Synology DS920", .storage, ip: "192.168.1.20", lastSeen: Fix.now.addingTimeInterval(-10 * 60))
        let snapshot = AskSnapshot(devices: [missed], events: [], lastScan: Fix.now.addingTimeInterval(-2 * 60), now: Fix.now, calendar: Fix.calendar)
        let status = AskToolbox(snapshot: snapshot).deviceStatus("the NAS")
        #expect(status.hasPrefix("Synology DS920 did not answer the scan 2 minutes ago (2026-11-23 11:58 AM). Last seen 10 minutes ago"))
        #expect(!status.lowercased().contains("online"))
    }

    @Test func aNetworkNeverScannedGivesNoStatus() {
        let snapshot = AskSnapshot(devices: [Self.staleNAS], events: [], lastScan: nil, now: Fix.now, calendar: Fix.calendar)
        let status = AskToolbox(snapshot: snapshot).deviceStatus("the NAS")
        #expect(status.hasPrefix("Synology DS920: this network hasn't been scanned yet, so its status is not known. Last seen 40 minutes ago"))
    }

    @Test func aScanWithinTheToleranceCountsAsAnswered() {
        // The Mac stamps lastSeen while merging, a moment before the profile's lastScanned.
        let device = Fix.device("Synology DS920", .storage, ip: "192.168.1.20", lastSeen: Fix.now.addingTimeInterval(-90))
        let snapshot = AskSnapshot(
            devices: [device], events: [], lastScan: Fix.now, lastScanTolerance: 5 * 60, now: Fix.now, calendar: Fix.calendar
        )
        #expect(snapshot.answeredLastScan(device))
        #expect(!AskSnapshot(devices: [device], events: [], lastScan: Fix.now, now: Fix.now, calendar: Fix.calendar).answeredLastScan(device))
    }

    // MARK: - The answer

    @Test func aDeviceSeenFortyMinutesAgoIsNeverDescribedAsOnlineNow() async {
        let calls: [AskToolCall] = [.findDevices("all")]
        for claim in [
            "Synology DS920 is online.",
            "Synology DS920 is online now.",
            "Yes, Synology DS920 is up.",
            "Synology DS920 is currently connected.",
            "Online: Synology DS920.",
            "Synology DS920 is not slow and is online.",
            "1 device is online: Synology DS920."
        ] {
            let answer = await ask("What's online?", calls: calls, answer: claim, snapshot: Self.stale)
            #expect(answer.text == nil, "accepted \(claim)")
            // The app says why there's no answer instead of "I couldn't look that up."
            #expect(answer.shownText == AskNetwork.staleFallback)
            // The citation and the app's freshness line still show.
            #expect(answer.devices.map(\.id) == [Self.staleNAS.id])
            #expect(answer.freshness == "Not checked recently: the last scan was 40 minutes ago (2026-11-23 11:20 AM).")
        }
    }

    @Test func aRejectedAnswerOnANetworkNeverScannedSaysSo() async {
        let snapshot = AskSnapshot(devices: [Self.staleNAS], events: [], lastScan: nil, now: Fix.now, calendar: Fix.calendar)
        let answer = await ask("What's online?", calls: [.findDevices("all")], answer: "Synology DS920 is online.", snapshot: snapshot)
        #expect(answer.text == nil)
        #expect(answer.shownText == "This network hasn't been scanned yet.")
        #expect(answer.devices.map(\.id) == [Self.staleNAS.id])
        #expect(answer.freshness == snapshot.freshnessNote)
    }

    @Test func aGenuineLookupFailureStillSaysSoOnAStaleNetwork() async {
        // No tool ran: nothing was looked up, so the stale wording would claim too much.
        let noCalls = await ask("What's online?", calls: [], answer: "Everything is fine.", snapshot: Self.stale)
        #expect(noCalls.shownText == AskNetwork.fallback)
        // The model failed (an unknown question to the script) after no status was stated.
        let failed = await AskNetwork.answer(
            "Unknown?", snapshot: Self.stale, pinnedDeviceID: nil, model: ScriptedAskModel(scripts: [:])
        )
        #expect(failed.shownText == AskNetwork.fallback)
        // A rejected answer from tools that stated no status (events) keeps the plain fallback too.
        let events = await ask("What joined?", calls: [.events(range: "last7Days", type: "joined")],
                               answer: "Five devices joined.", snapshot: Self.stale)
        #expect(events.shownText == AskNetwork.fallback)
    }

    @Test func aRejectedAnswerAfterAFreshScanKeepsThePlainFallback() async {
        let snapshot = AskSnapshot(devices: [Fix.nas], events: [], lastScan: Fix.now, now: Fix.now, calendar: Fix.calendar)
        let answer = await ask("Is the NAS up?", calls: [.deviceStatus("NAS")], answer: "Synology DS920 had 9 drops.", snapshot: snapshot)
        #expect(answer.shownText == AskNetwork.fallback)
    }

    @Test func aStaleAnswerWordedAsThePastOrANegationIsShown() async {
        for text in [
            "Synology DS920 answered the last scan, 40 minutes ago, and was online then; it has not been checked recently.",
            // The real model's wording on the 40-minute snapshot (probe, 2026-11-25).
            "Synology DS920 was last seen 40 minutes ago. Its status is not confirmed as online.",
            "Synology DS920 isn't known to be online now; it was last seen 40 minutes ago.",
            "Synology DS920 was last seen 40 minutes ago. Its online status is unknown.",
            "Synology DS920 was last seen 40 minutes ago. Whether it is online now is not known."
        ] {
            let answer = await ask("What's online?", calls: [.findDevices("all")], answer: text, snapshot: Self.stale)
            #expect(answer.text == text)
        }
    }

    @Test func aRepeatedHandleIsLeftOut() async {
        let text = "Synology DS920 (id dev-a) was last seen 40 minutes ago. Whether it is online now is not known."
        let answer = await ask("Is the NAS up?", calls: [.deviceStatus("NAS")], answer: text, snapshot: Self.stale)
        #expect(answer.text == "Synology DS920 was last seen 40 minutes ago. Whether it is online now is not known.")
        #expect(AskNetwork.withoutHandles("Ring Doorbell (ID dev-c) and NAS (dev-ab).") == "Ring Doorbell and NAS.")
    }

    @Test func aFreshAnswerMayRepeatTheAppsFreshness() async {
        let snapshot = AskSnapshot(
            devices: [Fix.nas], events: [], lastScan: Fix.now.addingTimeInterval(-3 * 60), now: Fix.now, calendar: Fix.calendar
        )
        let text = "Synology DS920 is online as of the scan 3 minutes ago, last seen less than a minute ago."
        let answer = await ask("Is the NAS up?", calls: [.deviceStatus("NAS")], answer: text, snapshot: snapshot)
        #expect(answer.text == text)
        #expect(answer.freshness == "Device status as of the scan 3 minutes ago (2026-11-23 11:57 AM).")
    }

    @Test func aFreshScanStillRejectsOnlineForADeviceThatMissedIt() async {
        let missed = Fix.device("Synology DS920", .storage, ip: "192.168.1.20", lastSeen: Fix.now.addingTimeInterval(-10 * 60))
        let snapshot = AskSnapshot(
            devices: [missed, Fix.appleTV], events: [], lastScan: Fix.now, now: Fix.now, calendar: Fix.calendar
        )
        let calls: [AskToolCall] = [.findDevices("all")]
        #expect(await ask("What's online?", calls: calls, answer: "Synology DS920 is online.", snapshot: snapshot).text == nil)
        // The device that answered may be called online, beside one that didn't.
        let mixed = "Synology DS920 did not answer the last scan, but Living Room Apple TV is online."
        #expect(await ask("What's online?", calls: calls, answer: mixed, snapshot: snapshot).text == mixed)
    }

    @Test func anAnswerWithoutDevicesHasNoFreshnessLine() async {
        let answer = await ask("What joined this week?", calls: [.events(range: "last7Days", type: "joined")],
                               answer: "No devices joined.", snapshot: AskSnapshot(
                                   devices: [], events: [], lastScan: Fix.now, now: Fix.now, calendar: Fix.calendar
                               ))
        #expect(answer.freshness == nil)
    }
}
