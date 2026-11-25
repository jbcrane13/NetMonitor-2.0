import Testing
import Foundation
@testable import NetMonitorCore

/// The model never states presence (#452, lead decision 2026-11-25: the app computes, the model
/// words). Sentences that say a device is online, offline, up, reachable and the like are dropped;
/// the app shows each cited device's status, last seen and the freshness line instead.
@Suite("AskPresenceFilter")
struct AskPresenceFilterTests {
    typealias Fix = AskFixture

    private static let fortyMinutesAgo = Fix.now.addingTimeInterval(-40 * 60)
    private static let staleNAS = Fix.device("Synology DS920", .storage, ip: "192.168.1.20", lastSeen: fortyMinutesAgo, latency: 2)
    private static let stale = AskSnapshot(
        devices: [staleNAS], events: [], lastScan: fortyMinutesAgo, now: Fix.now, calendar: Fix.calendar
    )
    /// A fresh scan two minutes ago that the printer missed (still online in grace), and an offline TV.
    private static let missedPrinter = Fix.device("Brother HL-L2350DW", .printer, ip: "192.168.1.57", lastSeen: Fix.now.addingTimeInterval(-600))
    private static let offlineTV = Fix.device("Living Room Apple TV", .tv, ip: "192.168.1.41", status: .offline)
    private static let fresh = AskSnapshot(
        devices: [missedPrinter, Fix.nas, offlineTV], events: [], lastScan: Fix.now.addingTimeInterval(-120),
        now: Fix.now, calendar: Fix.calendar
    )

    private func ask(_ question: String, calls: [AskToolCall], answer: String, snapshot: AskSnapshot) async -> AskAnswer {
        let model = ScriptedAskModel(scripts: [question: AskScript(calls: calls, answer: answer)])
        return await AskNetwork.answer(question, snapshot: snapshot, pinnedDeviceID: nil, model: model)
    }

    // MARK: - The lead's blocker scenarios

    @Test(arguments: [
        "Your printer is online.",
        "All devices are online.",
        "Yes.",
        "Yes, it is."
    ])
    func presenceAfterAFreshScanIsNeverTheModels(_ claim: String) async {
        let answer = await ask("Is the printer up?", calls: [.findDevices("all")], answer: claim, snapshot: Self.fresh)
        #expect(answer.text == nil, "kept: \(claim)")
        // The app says it instead: three devices looked up, two online (the printer within grace).
        #expect(answer.shownText == "2 of 3 devices are online as of the scan 2 minutes ago.")
        #expect(answer.devices.map(\.presence) == [.online, .online, .offline])
    }

    @Test(arguments: [
        "Synology DS920 has been online all day.",
        "Synology DS920 is active.",
        "Synology DS920 is available.",
        "Synology DS920 is awake.",
        "An unknown device is online.",
        "Synology DS920 is reachable on the network.",
        "Synology DS920 is back.",
        "Synology DS920 is up and responding.",
        "Synology DS920 is down."
    ])
    func presenceOnAStaleScanIsNeverTheModels(_ claim: String) async {
        let answer = await ask("Is the NAS up?", calls: [.deviceStatus("NAS")], answer: claim, snapshot: Self.stale)
        #expect(answer.text == nil, "kept: \(claim)")
        #expect(answer.shownText == AskNetwork.staleFallbackOne)
        #expect(answer.devices.map(\.presence) == [.notCheckedRecently])
        #expect(answer.freshness == Self.stale.freshnessNote)
    }

    @Test func didNotAnswerIsPresenceToo() async {
        // Real model, fresh scan (probe, 2026-11-25).
        let text = "Brother HL-L2350DW did not answer the last scan."
        let answer = await ask("Which devices are offline right now?", calls: [.findDevices("all")], answer: text, snapshot: Self.fresh)
        #expect(answer.text == nil)
    }

    @Test func aListUnderADroppedHeadingIsDroppedWithIt() async {
        // Real model, stale scan: the heading said what the list was; the list alone would still imply it.
        let text = """
        The following devices answered the last scan:
        - Synology DS920, storage, address 192.168.1.20
        """
        let answer = await ask("What's online?", calls: [.findDevices("all")], answer: text, snapshot: Self.stale)
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.staleFallbackOne)
        // A list under a heading that stays is kept.
        let kept = "Saved devices:\n- Synology DS920, storage, address 192.168.1.20"
        #expect(AskPresenceFilter.filtered(kept, outputs: []) == "Saved devices: - Synology DS920, storage, address 192.168.1.20")
    }

    @Test(arguments: [
        "Synology DS920 is idle.",
        "Synology DS920 is running.",
        "Synology DS920 is working fine.",
        "Synology DS920 is live.",
        "Synology DS920 is present.",
        "Synology DS920 is missing.",
        "Synology DS920 is on.",
        "Synology DS920 is turned off.",
        "Synology DS920 is powered on.",
        "Synology DS920 was unplugged.",
        "Synology DS920 dropped off.",
        "Synology DS920 appeared in the last scan.",
        "Synology DS920 was found by the scan.",
        "Synology DS920 is visible.",
        "Synology DS920 is detected.",
        "Its status is good.",
        "Synology DS920 is sleeping.",
        "Synology DS920 is pingable.",
        "Yep.",
        "Yeah, it is.",
        "Nope.",
        "Synology DS920 is online 2 times faster.",
        "Synology DS920 is up 3 times today."
    ])
    func moreWaysToStatePresenceAreDropped(_ claim: String) async {
        let answer = await ask("Is the NAS up?", calls: [.deviceStatus("NAS")], answer: claim, snapshot: Self.stale)
        #expect(answer.text == nil, "kept: \(claim)")
    }

    @Test func onlyADropCountIsHistory() {
        for kept in ["Ring Doorbell went offline 2 times.", "Ring Doorbell went offline once.", "Ring Doorbell has gone offline twice."] {
            #expect(!AskPresenceFilter.statesPresence(kept), "dropped: \(kept)")
        }
    }

    @Test func theRestOfTheModelsTextIsShown() async {
        let text = "Synology DS920 is online. Its address is 192.168.1.20."
        let answer = await ask("Where is the NAS?", calls: [.deviceStatus("NAS")], answer: text, snapshot: Self.fresh)
        #expect(answer.text == "Its address is 192.168.1.20.")
    }

    @Test func aCountOfDropsIsHistoryNotPresence() async {
        let text = "Ring Doorbell went offline 2 times and had 2 latency spikes."
        let answer = await ask("Which devices have been flaky?", calls: [.flakyDevices("last7Days")], answer: text, snapshot: Fix.snapshot)
        #expect(answer.text == text)
    }

    // MARK: - Freshness wording

    @Test func aTimeAgoTheToolsDidNotWriteIsDropped() async {
        let text = "Synology DS920 was last seen 5 minutes ago. Its address is 192.168.1.20."
        let answer = await ask("When was the NAS seen?", calls: [.deviceStatus("NAS")], answer: text, snapshot: Self.stale)
        #expect(answer.text == "Its address is 192.168.1.20.")
    }

    @Test func aTimeAgoTheToolsWroteIsKept() async {
        let text = "Synology DS920 was last seen 40 minutes ago (2026-11-23 11:20 AM)."
        let answer = await ask("When was the NAS seen?", calls: [.deviceStatus("NAS")], answer: text, snapshot: Self.stale)
        #expect(answer.text == text)
    }

    @Test(arguments: [
        "Synology DS920 was seen just now.",
        "Synology DS920 was seen moments ago.",
        "Synology DS920 was recently checked.",
        "Synology DS920 was recently seen."
    ])
    func vagueFreshnessIsDropped(_ text: String) async {
        let answer = await ask("When was the NAS seen?", calls: [.deviceStatus("NAS")], answer: text, snapshot: Self.stale)
        #expect(answer.text == nil, "kept: \(text)")
    }

    // MARK: - What the app shows instead

    @Test func oneDeviceGetsItsOwnSummary() async {
        let missed = await ask("Is the printer up?", calls: [.findDevices("printer")], answer: "Yes.", snapshot: Self.fresh)
        #expect(missed.shownText == "Brother HL-L2350DW is online as of the scan 2 minutes ago.")
        let offline = await ask("Is the TV up?", calls: [.findDevices("Apple TV")], answer: "Yes.", snapshot: Self.fresh)
        #expect(offline.shownText == "Living Room Apple TV is offline as of the scan 2 minutes ago.")
    }

    @Test func theStaleFallbackIsSingularForOneDevice() async {
        let one = await ask("Is the NAS up?", calls: [.deviceStatus("NAS")], answer: "Yes.", snapshot: Self.stale)
        #expect(one.shownText == "This device hasn't been checked recently. Its last-seen time is below.")
        let printer = Fix.device("Brother HL-L2350DW", .printer, ip: "192.168.1.57", status: .offline, lastSeen: Self.fortyMinutesAgo)
        let two = AskSnapshot(
            devices: [Self.staleNAS, printer], events: [], lastScan: Self.fortyMinutesAgo, now: Fix.now, calendar: Fix.calendar
        )
        let both = await ask("What's online?", calls: [.findDevices("all")], answer: "Yes.", snapshot: two)
        #expect(both.shownText == "These devices haven't been checked recently. Their last-seen times are below.")
        // The saved "offline" doesn't show through an old scan.
        #expect(both.devices.map(\.presence) == [.notCheckedRecently, .notCheckedRecently])
    }

    @Test func eachCitationCarriesTheAppsStatusAndLastSeen() async {
        let answer = await ask("What's there?", calls: [.findDevices("all")], answer: "Three devices are saved.", snapshot: Self.fresh)
        #expect(answer.text == "Three devices are saved.")
        let printer = answer.devices.first { $0.id == Self.missedPrinter.id }
        // Missed the recent scan but within grace: Online, with its real last seen (lead, #583).
        #expect(printer?.presence == .online)
        #expect(printer?.lastSeen == Self.missedPrinter.lastSeen)
        #expect(answer.freshness == Self.fresh.freshnessNote)
    }

    @Test func presenceLabels() {
        // Blake's three states (#583).
        #expect(AskPresence.online.label == "Online")
        #expect(AskPresence.offline.label == "Offline")
        #expect(AskPresence.notCheckedRecently.label == "Not checked recently")
        #expect(Fix.snapshot.presence(of: Fix.printer) == .offline)
        // No scan, or an old one: not checked recently, whatever the saved status says.
        let unscanned = AskSnapshot(devices: [Fix.nas], events: [], lastScan: nil, now: Fix.now, calendar: Fix.calendar)
        #expect(unscanned.presence(of: Fix.nas) == .notCheckedRecently)
        let old = AskSnapshot(
            devices: [Fix.printer], events: [], lastScan: Self.fortyMinutesAgo, now: Fix.now, calendar: Fix.calendar
        )
        #expect(old.presence(of: Fix.printer) == .notCheckedRecently)
        #expect(Self.stale.presence(of: Self.staleNAS) == .notCheckedRecently)
    }

    // MARK: - Events

    @Test func eventsCiteTheirDevicesWithTheFreshnessLine() async {
        // An event written without a device id still cites the device its title names.
        let unlinked = NetworkEvent(type: .deviceLeft, timestamp: Fix.date(23, 10), title: "Device Left: Synology DS920")
        let snapshot = AskSnapshot(
            devices: Fix.devices, events: Fix.events + [unlinked], lastScan: Fix.now, now: Fix.now, calendar: Fix.calendar
        )
        let answer = await ask("What left today?", calls: [.events(range: "today", type: "left")],
                               answer: "Two devices left today.", snapshot: snapshot)
        #expect(answer.devices.map(\.id) == [Fix.nas.id, Fix.printer.id])
        #expect(answer.freshness == snapshot.freshnessNote)
    }
}
