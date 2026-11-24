import Foundation
import NetworkScanKit
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

    @Test func aDurationIsKeptOnlyWhenTheWordsStateIt() {
        func duration(_ seconds: Int, _ input: String) -> RuleIntent {
            RuleIntent.normalized(kind: "deviceOffline", device: "NAS", thresholdMilliseconds: nil, durationSeconds: seconds,
                                  portPreset: nil, input: input)
        }
        #expect(duration(300, "Tell me if the NAS is down for more than five minutes").durationSeconds == 300)
        #expect(duration(1800, "If the Apple TV latency is above 80ms for half an hour, notify me").durationSeconds == 1800)
        #expect(duration(120, "NAS down for 2 min").durationSeconds == 120)
        #expect(duration(1500, "NAS down twenty five minutes").durationSeconds == 1500)
        #expect(duration(3600, "the NAS is off for an hour").durationSeconds == 3600)
        // The real model gave 60 s for "every minute" (#450 probe): no duration is stated.
        let every = duration(60, "Ping the NAS every minute and tell me if it's slow")
        #expect(every.durationSeconds == nil)
        #expect(every.durationWasDropped)
        let wrong = duration(600, "Tell me if the NAS is down for more than five minutes")
        #expect(wrong.durationSeconds == nil, "Ten minutes isn't what the user said")
        #expect(wrong.durationWasDropped)
        #expect(!duration(300, "the NAS for 5 minutes").durationWasDropped)
    }

    /// A correct model answer must survive: a dropped duration saves a rule that alerts at once.
    @Test func aDurationInLessCommonWordsDecimalsOrTwoPartsIsKept() {
        func duration(_ seconds: Int, _ input: String) -> Int? {
            RuleIntent.normalized(kind: "deviceOffline", device: "NAS", thresholdMilliseconds: nil, durationSeconds: seconds,
                                  portPreset: nil, input: input).durationSeconds
        }
        #expect(duration(780, "alert if the NAS is offline for thirteen minutes") == 780)
        #expect(duration(4200, "alert if the NAS is offline for seventy minutes") == 4200)
        #expect(duration(5400, "alert me if the NAS is down for 1.5 hours") == 5400)
        #expect(duration(5400, "alert me if the NAS is down for 1 hour and 30 minutes") == 5400)
        #expect(duration(18000, "alert me if the NAS is down for 1.5 hours") == nil, "Not 5 hours")
        #expect(duration(1800, "alert me if the NAS is down for 1 hour and 30 minutes") == nil, "Part of the duration isn't it")
    }

    @Test func spokenDurationsReadHalvesAndShortUnits() {
        #expect(SpokenDuration.seconds(in: "down for an hour and a half") == [5400])
        #expect(SpokenDuration.seconds(in: "two hours and a half") == [9000])
        #expect(SpokenDuration.seconds(in: "for 5m") == [300])
        #expect(SpokenDuration.seconds(in: "for 5 min") == [300])
        #expect(SpokenDuration.seconds(in: "for 2h") == [7200])
        #expect(SpokenDuration.seconds(in: "5 minutes and a second device joins") == [300, 1])
        #expect(SpokenDuration.seconds(in: "1 hour 30 minutes") == [5400])
    }

    @Test func spokenDurationsReadDigitsWordsAndUnits() {
        #expect(SpokenDuration.seconds(in: "down 5min or 90s") == [300, 90])
        #expect(SpokenDuration.seconds(in: "half a minute") == [30])
        #expect(SpokenDuration.seconds(in: "250 ms for 2 minutes") == [120])
        #expect(SpokenDuration.seconds(in: "every minute").isEmpty)
        for (word, minutes) in [("thirteen", 13), ("fourteen", 14), ("sixteen", 16), ("seventeen", 17), ("nineteen", 19),
                                ("seventy", 70), ("eighty two", 82)] {
            #expect(SpokenDuration.seconds(in: "offline for \(word) minutes") == [minutes * 60])
        }
        #expect(SpokenDuration.seconds(in: "down for 1.5 hours.") == [5400])
        #expect(SpokenDuration.seconds(in: "down 2 hours 15 minutes") == [8100])
        #expect(SpokenDuration.seconds(in: "above 5 seconds for 2 minutes") == [5, 120], "Not adjacent: two durations")
        #expect(SpokenDuration.seconds(in: "ping 192.168.1.40 for 5 minutes") == [300])
        #expect(SpokenDuration.seconds(in: "down for 5 minutes and a second device joins") == [300, 1])
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
        #expect(DevicePhraseResolver.resolve("the NAS", among: devices) == .one(nas))
    }

    @Test func wordsMatchWholeWordsNotParts() {
        #expect(DevicePhraseResolver.resolve("NAS", among: [jonas]) == .none, "\"nas\" is inside \"Jonas\"")
    }

    @Test func aNameMakerOrTypeWordCanEachMatch() {
        #expect(DevicePhraseResolver.resolve("Synology", among: devices) == .one(nas))
        #expect(DevicePhraseResolver.resolve("my office printer", among: devices) == .one(printer))
        #expect(DevicePhraseResolver.resolve("Apple TV", among: devices) == .one(appleTV))
        #expect(DevicePhraseResolver.resolve("the Synology NAS", among: devices) == .one(nas))
    }

    /// #571: a device only the scan knows gets its type from Core's inference, so "the printer" names it.
    @Test func aScannedDeviceGetsAnInferredTypeSoATypeWordNamesIt() {
        let scanned = DiscoveredDevice(
            ipAddress: "192.168.1.30", hostname: "office-laser", vendor: nil, macAddress: "02:00:00:01:00:30",
            latency: 4, discoveredAt: Date(), source: .local, openPorts: [631, 9100]
        )
        let device = RuleDevice(scanned: scanned)
        #expect(device.deviceType == .printer)
        #expect(device.openPorts == [631, 9100])
        #expect(DevicePhraseResolver.resolve("the printer", among: [device, nas]) == .one(device))
    }

    @Test func twoMatchesAreAmbiguous() {
        #expect(DevicePhraseResolver.resolve("the printer", among: devices) == .several([printer, laserJet]))
    }

    @Test func anExactNameWinsOverOtherMatches() {
        let named = RuleDevice(id: UUID(), displayName: "Printer", deviceType: .printer, maker: nil, ipAddress: "10.0.0.42")
        #expect(DevicePhraseResolver.resolve("the printer", among: devices + [named]) == .one(named))
    }

    @Test func noMatchOrNoWordsIsNone() {
        #expect(DevicePhraseResolver.resolve("the garage door", among: devices) == .none)
        #expect(DevicePhraseResolver.resolve("the", among: devices) == .none)
    }
}
