import Testing
import Foundation
@testable import NetMonitorCore

/// One question through the pipeline (#452): a scripted model calls the tools, then the app checks
/// the answer against what they returned and lists what they cited.
@Suite("AskNetwork")
struct AskNetworkTests {
    typealias Fix = AskFixture

    private func ask(_ question: String, calls: [AskToolCall], answer: String, pinned: UUID? = nil) async -> AskAnswer {
        let model = ScriptedAskModel(scripts: [question: AskScript(calls: calls, answer: answer)])
        return await AskNetwork.answer(question, snapshot: Fix.snapshot, pinnedDeviceID: pinned, model: model)
    }

    @Test func aGroundedAnswerIsShownWithItsCitations() async {
        let answer = await ask("Is the printer up?", calls: [.findDevices("printer")],
                               answer: "No. Brother HL-L2350DW is offline; it was last seen at 9:14 AM on 2026-11-23.")
        #expect(answer.text == "No. Brother HL-L2350DW is offline; it was last seen at 9:14 AM on 2026-11-23.")
        #expect(answer.devices == [AskAnswer.DeviceCitation(id: Fix.printer.id, name: "Brother HL-L2350DW")])
        #expect(answer.events.isEmpty)
    }

    @Test func anAnswerWithoutToolCallsIsUngrounded() async {
        // The spike's case 7: no tool called, yet "the home router shows high latency".
        let answer = await ask("Why is the internet slow tonight?", calls: [], answer: "The home router shows high latency and packet loss.")
        #expect(answer.text == nil)
        #expect(answer.shownText == AskNetwork.fallback)
    }

    @Test func anInventedNumberIsRejected() async {
        let answer = await ask("Is the printer up?", calls: [.findDevices("printer")],
                               answer: "Brother HL-L2350DW has been offline for 3 hours.")
        #expect(answer.text == nil)
        // What the tools found is still listed.
        #expect(answer.devices.map(\.id) == [Fix.printer.id])
    }

    @Test func aRealDeviceTheToolsDidNotReturnIsRejected() async {
        let answer = await ask("Is the printer up?", calls: [.findDevices("printer")],
                               answer: "Brother HL-L2350DW is offline, but Synology DS920 is online.")
        #expect(answer.text == nil)
    }

    @Test func aMadeUpNameIsRejected() async {
        let answer = await ask("Is the printer up?", calls: [.findDevices("printer")],
                               answer: "Brother HL-L2350DW is offline and the Fridge is online.")
        #expect(answer.text == nil)
    }

    @Test func aCauseTheToolsDidNotRecordIsRejected() async {
        let answer = await ask("Why is the internet slow tonight?", calls: [.flakyDevices("today")],
                               answer: "The internet is slow because the Ring Doorbell had 2 latency spikes.")
        #expect(answer.text == nil)
    }

    @Test func aNameTheToolsDidNotFindIsRejectedEvenWhenTheQuestionHasItsWord() async {
        let script = AskScript(calls: [.findDevices("printer")], answer: "Office Printer is offline.")
        let model = ScriptedAskModel(scripts: ["Is the printer up?": script])
        let empty = AskSnapshot(devices: [], events: [], now: Fix.now, calendar: Fix.calendar)
        let answer = await AskNetwork.answer("Is the printer up?", snapshot: empty, pinnedDeviceID: nil, model: model)
        #expect(answer.text == nil)
    }

    @Test func eventsAreCitedWithTheirTimes() async {
        let answer = await ask("What joined this week?", calls: [.events(range: "last7Days", type: "joined")],
                               answer: "Two devices joined: Kitchen iPad on 2026-11-21 and ESP_3F21A9 on 2026-11-19.")
        #expect(answer.text != nil)
        #expect(answer.events.map(\.id) == [Fix.iPadJoined.id, Fix.espJoined.id])
        #expect(answer.events.first?.timestamp == Fix.iPadJoined.timestamp)
        #expect(answer.devices.map(\.id) == [Fix.iPad.id, Fix.esp.id])
    }

    @Test func flakyNamesTheDevicesTheAppRanked() async {
        let answer = await ask("Which devices have been flaky?", calls: [.flakyDevices("last7Days")],
                               answer: "Ring Doorbell went offline 2 times and Nest Thermostat went offline once, with latency spikes.")
        #expect(answer.text != nil)
        #expect(answer.devices.map(\.name) == ["Ring Doorbell", "Nest Thermostat"])
    }

    @Test func callsPastTheHardStopEndTheTurnWithoutAnAnswer() async {
        let calls = Array(repeating: AskToolCall.findDevices("printer"), count: AskToolbox.hardStop + 1)
        let answer = await ask("Is the printer up?", calls: calls, answer: "Brother HL-L2350DW is offline.")
        #expect(answer.text == nil)
    }

    @Test func callsPastTheSoftCapStillLetTheModelAnswer() async {
        let calls = Array(repeating: AskToolCall.findDevices("printer"), count: 6)
        let answer = await ask("Is the printer up?", calls: calls, answer: "Brother HL-L2350DW is offline.")
        #expect(answer.text == "Brother HL-L2350DW is offline.")
    }

    @Test func aPickedDeviceIsTheOneTheToolsUse() async {
        let answer = await ask("Is the Office MacBook up?", calls: [.deviceStatus("Apple")], answer: "Office MacBook is online.",
                               pinned: Fix.macBook.id)
        #expect(answer.devices.map(\.id) == [Fix.macBook.id])
        #expect(answer.text == "Office MacBook is online.")
    }

    @Test func aFailedModelShowsTheFallback() async {
        let answer = await AskNetwork.answer("Is the printer up?", snapshot: Fix.snapshot, pinnedDeviceID: nil, model: ScriptedAskModel(scripts: [:]))
        #expect(answer.text == nil)
        #expect(answer.devices.isEmpty)
    }

    @Test func theInstructionsGiveTodayAndTheToolRules() {
        let instructions = AskNetwork.instructions(for: Fix.snapshot)
        #expect(instructions.contains("Today is Monday, 2026-11-23."))
        #expect(instructions.contains("flakyDevices"))
    }
}
