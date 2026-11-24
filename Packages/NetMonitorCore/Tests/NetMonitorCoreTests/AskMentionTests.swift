import Testing
import Foundation
@testable import NetMonitorCore

/// Before the model is asked, the app finds a device phrase in the question that fits several
/// devices, so the user picks one (#452).
@Suite("AskMention")
struct AskMentionTests {
    typealias Fix = AskFixture
    static let laser = Fix.device("HL-L2350DW Upstairs", .printer, maker: "Brother", ip: "192.168.1.58")
    static let twoPrinters = Fix.devices + [laser]

    @Test func aTypeWordThatFitsSeveralDevicesAsksWhichOne() {
        let mention = AskMention.ambiguous(in: "Is the printer up?", among: Self.twoPrinters)
        #expect(mention?.phrase == "printer")
        #expect(mention?.devices == [Fix.printer, Self.laser])
    }

    @Test func aMakerWordThatFitsSeveralAsksToo() {
        #expect(AskMention.ambiguous(in: "is my Apple device online", among: Fix.devices)?.devices == [Fix.appleTV, Fix.macBook, Fix.iPad])
    }

    @Test func oneFitIsNotAmbiguous() {
        #expect(AskMention.ambiguous(in: "Is the printer up?", among: Fix.devices) == nil)
        #expect(AskMention.ambiguous(in: "How has the NAS latency been today?", among: Fix.devices) == nil)
    }

    @Test func questionsWithoutADeviceAskNothing() {
        #expect(AskMention.ambiguous(in: "What joined this week?", among: Self.twoPrinters) == nil)
        #expect(AskMention.ambiguous(in: "Which devices have been flaky?", among: Self.twoPrinters) == nil)
    }

    @Test func aRoomWordSharedBySeveralNamesIsNotAPicker() {
        let speaker = Fix.device("Living Room Speaker", .speaker, maker: "Sonos", ip: "192.168.1.42")
        #expect(AskMention.ambiguous(in: "Is the living room slow?", among: Fix.devices + [speaker]) == nil)
    }

    @Test func aLongerPhraseThatFitsOneWinsOverItsTypeWord() {
        // "Brother printer" fits both; "upstairs printer" fits one.
        #expect(AskMention.ambiguous(in: "is the upstairs printer up", among: Self.twoPrinters) == nil)
    }

    @Test func theChosenDeviceReplacesThePhrase() {
        let mention = AskMention.ambiguous(in: "Is the printer up?", among: Self.twoPrinters)
        #expect(mention?.question(choosing: Self.laser) == "Is the HL-L2350DW Upstairs up?")
    }
}
