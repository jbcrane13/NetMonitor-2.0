import Testing
import Foundation
@testable import NetMonitorCore

/// The Ask card's state on both apps (#452), driven with a scripted model.
@Suite("AskState")
@MainActor
struct AskStateTests {
    typealias Fix = AskFixture
    static let laser = Fix.device("HL-L2350DW Upstairs", .printer, maker: "Brother", ip: "192.168.1.58")

    final class Scanning {
        var value = false
    }

    private func makeState(
        _ scripts: [String: AskScript],
        available: Bool = true,
        devices: [AskDevice] = Fix.devices,
        scanning: Scanning = Scanning()
    ) -> AskState {
        AskState(
            model: ScriptedAskModel(scripts: scripts, isAvailable: available),
            snapshot: { AskSnapshot(devices: devices, events: Fix.events, lastScan: Fix.now, now: Fix.now, calendar: Fix.calendar) },
            isScanning: { scanning.value }
        )
    }

    private static let printerScript = AskScript(calls: [.findDevices("printer")], answer: "Brother HL-L2350DW is a printer.")

    @Test func aQuestionIsAnsweredWithCitations() async {
        let state = makeState(["Is the printer up?": Self.printerScript])
        await state.ask("Is the printer up?")
        guard case let .answered(answer) = state.phase else {
            Issue.record("not answered: \(state.phase)")
            return
        }
        #expect(answer.text == "Brother HL-L2350DW is a printer.")
        #expect(answer.devices.map(\.id) == [Fix.printer.id])
    }

    @Test func theCardIsHiddenWhenTheModelIsUnavailable() async {
        let state = makeState(["Is the printer up?": Self.printerScript], available: false)
        #expect(!state.isVisible)
        await state.ask("Is the printer up?")
        #expect(state.phase == .idle)
    }

    @Test func noQuestionRunsDuringAScan() async {
        let scanning = Scanning()
        scanning.value = true
        let state = makeState(["Is the printer up?": Self.printerScript], scanning: scanning)
        await state.ask("Is the printer up?")
        #expect(state.phase == .stopped(AskState.scanMessage))
    }

    @Test func severalMatchingDevicesAreOfferedBeforeTheModelIsAsked() async {
        let script = AskScript(calls: [.findDevices("HL-L2350DW Upstairs")], answer: "HL-L2350DW Upstairs is a printer.")
        let state = makeState(["Is the HL-L2350DW Upstairs up?": script], devices: Fix.devices + [Self.laser])
        await state.ask("Is the printer up?")
        #expect(state.phase == .needsDevice([Fix.printer, Self.laser]))
        await state.pick(Self.laser)
        guard case let .answered(answer) = state.phase else {
            Issue.record("not answered: \(state.phase)")
            return
        }
        #expect(state.question == "Is the HL-L2350DW Upstairs up?")
        #expect(answer.text == "HL-L2350DW Upstairs is a printer.")
        #expect(answer.devices.map(\.id) == [Self.laser.id])
    }

    @Test func cancelStopsTheQuestionAndDropsItsLateAnswer() async {
        let slow = AskScript(calls: [.findDevices("printer")], answer: "Brother HL-L2350DW is offline.", delay: .seconds(30))
        let state = makeState(["Is the printer up?": slow])
        let asking = Task { await state.ask("Is the printer up?") }
        while state.phase != .asking {
            await Task.yield()
        }
        state.cancel()
        await asking.value
        #expect(state.phase == .stopped(AskState.cancelledMessage))
    }

    @Test func anEmptyQuestionDoesNothing() async {
        let state = makeState([:])
        await state.ask("   ")
        #expect(state.phase == .idle)
    }

    @Test func resetGoesBackToTheField() async {
        let state = makeState(["Is the printer up?": Self.printerScript])
        await state.ask("Is the printer up?")
        state.reset()
        #expect(state.phase == .idle)
    }
}
