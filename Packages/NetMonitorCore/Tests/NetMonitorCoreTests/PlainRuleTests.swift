import Foundation
import Testing
@testable import NetMonitorCore

@Suite("Plain-English rules: intent and device resolution (#450)")
struct PlainRuleTests {
    // MARK: - Cleaning the model's answer

    @Test func anUnsupportedAnswerDropsEveryOtherField() {
        // The spike saw unsupported answers keep "weather" as the device and a zero duration.
        let intent = RuleIntent.normalized(
            kind: "unsupported", device: "weather", thresholdMilliseconds: 80, durationSeconds: 0, portPreset: "web",
            input: "what's the weather tomorrow?"
        )
        #expect(intent == .unsupported)
    }

    @Test func anUnknownKindIsUnsupported() {
        let intent = RuleIntent.normalized(kind: "reboot", device: "router", thresholdMilliseconds: nil, durationSeconds: nil,
                                           portPreset: nil, input: "reboot the router")
        #expect(intent == .unsupported)
    }

    @Test func fieldsAreKeptOnlyForTheKindsThatUseThem() {
        let offline = RuleIntent.normalized(kind: "deviceOffline", device: " NAS ", thresholdMilliseconds: 90, durationSeconds: 300,
                                            portPreset: "web", input: "Tell me if the NAS is down for more than five minutes")
        #expect(offline == RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 300))
        let newDevice = RuleIntent.normalized(kind: "newDevice", device: "network", thresholdMilliseconds: nil, durationSeconds: 60,
                                              portPreset: nil, input: "tell me about new devices")
        #expect(newDevice == RuleIntent(kind: .newDevice))
        let scan = RuleIntent.normalized(kind: "portScan", device: "printer", thresholdMilliseconds: nil, durationSeconds: 30,
                                         portPreset: "web", input: "scan web ports on the printer")
        #expect(scan == RuleIntent(kind: .portScan, device: "printer", portPreset: .web))
    }

    @Test func aThresholdIsKeptOnlyWhenTheUserTypedItsDigits() {
        let typed = RuleIntent.normalized(kind: "latencyAbove", device: "Ring Doorbell", thresholdMilliseconds: 250, durationSeconds: 120,
                                          portPreset: nil, input: "Alert me when the Ring Doorbell's ping goes over 250 ms for 2 minutes")
        #expect(typed.thresholdMilliseconds == 250)
        #expect(typed.durationSeconds == 120)
        let invented = RuleIntent.normalized(kind: "latencyAbove", device: "NAS", thresholdMilliseconds: 200, durationSeconds: nil,
                                             portPreset: nil, input: "tell me if the NAS is slow")
        #expect(invented.thresholdMilliseconds == nil)
        let partial = RuleIntent.normalized(kind: "latencyAbove", device: "NAS", thresholdMilliseconds: 25, durationSeconds: nil,
                                            portPreset: nil, input: "NAS latency over 250ms")
        #expect(partial.thresholdMilliseconds == nil, "25 is not a number the user typed")
    }

    @Test func aPortScanWithoutAKnownPresetUsesCommonPorts() {
        let intent = RuleIntent.normalized(kind: "portScan", device: "printer", thresholdMilliseconds: nil, durationSeconds: nil,
                                           portPreset: "custom", input: "scan the printer")
        #expect(intent.portPreset == .common)
    }

    @Test func theFixedParserAnswersFromItsTableAndElseIsUnsupported() async {
        let parser = FixedRuleIntentParser.uiTest
        #expect(await parser.parse("  tell me if the NAS is down for more than five minutes ")
            == RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 300))
        #expect(await parser.parse("what's the weather") == .unsupported)
    }

    // MARK: - Device resolution

    private let nas = RuleDevice(id: UUID(), displayName: "Synology DS920", deviceType: .storage, maker: "Synology", ipAddress: "10.0.0.50")
    private let printer = RuleDevice(id: UUID(), displayName: "Office Printer", deviceType: .printer, maker: "Brother", ipAddress: "10.0.0.40")
    private let laserJet = RuleDevice(id: UUID(), displayName: "LaserJet", deviceType: .printer, maker: "HP", ipAddress: "10.0.0.41")
    private let jonas = RuleDevice(id: UUID(), displayName: "Jonas iPhone", deviceType: .phone, maker: "Apple", ipAddress: "10.0.0.60")
    private let appleTV = RuleDevice(id: UUID(), displayName: "Living Room", deviceType: .tv, maker: "Apple", ipAddress: "10.0.0.70")

    private var devices: [RuleDevice] { [nas, printer, laserJet, jonas, appleTV] }

    @Test func aTypeWordFindsTheDeviceTheModelNeverNames() {
        // The spike: the model never maps "NAS" to "Synology DS920" by itself.
        #expect(RuleDeviceResolver.resolve("the NAS", among: devices) == .one(nas))
    }

    @Test func wordsMatchWholeWordsNotParts() {
        #expect(RuleDeviceResolver.resolve("NAS", among: [jonas]) == .none, "\"nas\" is inside \"Jonas\"")
    }

    @Test func aNameMakerOrTypeWordCanEachMatch() {
        #expect(RuleDeviceResolver.resolve("Synology", among: devices) == .one(nas))
        #expect(RuleDeviceResolver.resolve("my office printer", among: devices) == .one(printer))
        #expect(RuleDeviceResolver.resolve("Apple TV", among: devices) == .one(appleTV))
        #expect(RuleDeviceResolver.resolve("the Synology NAS", among: devices) == .one(nas))
    }

    @Test func twoMatchesAreAmbiguous() {
        #expect(RuleDeviceResolver.resolve("the printer", among: devices) == .several([printer, laserJet]))
    }

    @Test func anExactNameWinsOverOtherMatches() {
        let named = RuleDevice(id: UUID(), displayName: "Printer", deviceType: .printer, maker: nil, ipAddress: "10.0.0.42")
        #expect(RuleDeviceResolver.resolve("the printer", among: devices + [named]) == .one(named))
    }

    @Test func noMatchOrNoWordsIsNone() {
        #expect(RuleDeviceResolver.resolve("the garage door", among: devices) == .none)
        #expect(RuleDeviceResolver.resolve("the", among: devices) == .none)
    }
}
