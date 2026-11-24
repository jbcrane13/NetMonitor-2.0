import Foundation
import Testing
@testable import NetMonitorCore

@Suite("Plain-English rules: drafts (#450)")
struct PlainRuleBuilderTests {
    private let nas = RuleDevice(id: UUID(), displayName: "Synology DS920", deviceType: .storage, maker: "Synology", ipAddress: "10.0.0.50")
    private let printer = RuleDevice(id: UUID(), displayName: "Office Printer", deviceType: .printer, maker: "Brother", ipAddress: "10.0.0.40")
    private let laserJet = RuleDevice(id: UUID(), displayName: "LaserJet", deviceType: .printer, maker: "HP", ipAddress: "10.0.0.41")
    private var devices: [RuleDevice] { [nas, printer, laserJet] }
    private let timing = RuleTiming(targetCheckInterval: 5, scanGrace: DeviceGracePolicy(missedScans: 3, interval: 900))
    static let portNote = "Background checks connect to the device's port 80, so a device that doesn't accept connections there shows as down."

    private func mac(_ intent: RuleIntent, targetHosts: Set<String> = [], chosen: RuleDevice? = nil) -> PlainRuleOutcome {
        PlainRuleBuilder.outcome(for: intent, devices: devices, platform: .mac, timing: timing, targetHosts: targetHosts, chosen: chosen)
    }

    private func iOS(_ intent: RuleIntent, targetHosts: Set<String> = []) -> PlainRuleOutcome {
        PlainRuleBuilder.outcome(for: intent, devices: devices, platform: .iOS, timing: timing, targetHosts: targetHosts)
    }

    // MARK: - macOS

    @Test func theNASExampleBecomesAnOfflineRuleOnTheDevicesIdentityWithItsDuration() throws {
        let outcome = mac(RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 300))
        guard case let .alert(draft) = outcome else { Issue.record("got \(outcome)")
        return
        }
        #expect(draft.rule.trigger == .wentOffline)
        // The name is a fallback for builds before #450, which don't read `deviceID`.
        #expect(draft.rule.conditions == AlertRuleConditions(device: "Synology DS920", deviceID: nas.id))
        #expect(draft.rule.minimumDuration == 300)
        #expect(draft.rule.name == "Offline for 5 minutes")
        #expect(draft.device == nas)
        #expect(draft.offersTarget, "No target watches the NAS yet")
    }

    @Test func theFallbackForOlderBuildsIsTheMACWhenKnown() {
        let withMAC = RuleDevice(id: UUID(), displayName: "Basement NAS", deviceType: .storage, maker: nil, ipAddress: "10.0.0.51",
                                 macAddress: "AA:BB:CC:00:00:51")
        let outcome = PlainRuleBuilder.outcome(for: RuleIntent(kind: .deviceOffline, device: "Basement NAS"), devices: [withMAC],
                                               platform: .mac, timing: timing, targetHosts: [])
        guard case let .alert(draft) = outcome else { Issue.record("got \(outcome)")
        return
        }
        #expect(draft.rule.conditions == AlertRuleConditions(device: "AA:BB:CC:00:00:51", deviceID: withMAC.id))
    }

    @Test func aDroppedDurationIsSaidOnBothPlatforms() {
        var intent = RuleIntent(kind: .deviceOffline, device: "NAS")
        intent.durationWasDropped = true
        guard case var .alert(draft) = mac(intent) else { Issue.record("not an alert")
        return
        }
        #expect(draft.notes(addingTarget: true, timing: timing) == [PlainRuleBuilder.droppedDurationNote])
        draft.rule.minimumDuration = 600
        #expect(!draft.notes(addingTarget: true, timing: timing).contains(PlainRuleBuilder.droppedDurationNote), "The user set one")
        guard case let .target(target) = iOS(intent) else { Issue.record("not a target")
        return
        }
        #expect(target.notes.last == PlainRuleBuilder.droppedDurationNote)
    }

    @Test func presetsAScannerLacksBecomeCustomPortLists() {
        #expect(PortScanPreset.wellKnown.customPortsText == "1-1024")
        #expect(PortScanPreset.extended.customPortsText == "1-10000")
        #expect(PortScanPreset.mail.customPortsText == "25,110,143,465,587,993,995")
    }

    @Test func noTargetIsOfferedWhenOneAlreadyWatchesTheDevice() {
        guard case let .alert(draft) = mac(RuleIntent(kind: .deviceOffline, device: "NAS"), targetHosts: ["10.0.0.50"]) else {
            Issue.record("not an alert")
            return
        }
        #expect(!draft.offersTarget)
        #expect(draft.hasTarget)
    }

    @Test func eachAlertKindMapsToItsTrigger() {
        func rule(_ intent: RuleIntent) -> AlertRule? {
            if case let .alert(draft) = mac(intent) {
                return draft.rule
            }
            return nil
        }
        #expect(rule(RuleIntent(kind: .deviceOnline, device: "Synology"))?.trigger == .cameOnline)
        #expect(rule(RuleIntent(kind: .deviceOnline, device: "Synology"))?.name == "Comes online")
        let newDevice = rule(RuleIntent(kind: .newDevice))
        #expect(newDevice?.trigger == .firstSeen)
        #expect(newDevice?.conditions == AlertRuleConditions())
        #expect(newDevice?.name == "New device joins")
        let latency = rule(RuleIntent(kind: .latencyAbove, device: "NAS", thresholdMilliseconds: 250, durationSeconds: 120))
        #expect(latency?.trigger == .latencyAbove(milliseconds: 250))
        #expect(latency?.minimumDuration == 120)
        #expect(latency?.name == "Latency above 250 ms for 2 minutes")
    }

    @Test func aMissingThresholdIsFilledInAndSaidSo() {
        guard case let .alert(draft) = mac(RuleIntent(kind: .latencyAbove, device: "NAS")) else { Issue.record("not an alert")
        return
        }
        #expect(draft.rule.trigger == .latencyAbove(milliseconds: 200))
        #expect(!draft.thresholdWasGiven)
        #expect(draft.notes(addingTarget: true, timing: timing).first
            == "You didn't give a threshold in milliseconds, so 200 ms is filled in. Check it.")
    }

    @Test func thePrinterScanBecomesAPortScanPresetNotARule() {
        #expect(mac(RuleIntent(kind: .portScan, device: "Office Printer", portPreset: .web)) == .portScan(device: printer, preset: .web))
    }

    @Test func anAmbiguousDeviceAsksForAPickAndThePickIsUsed() {
        let intent = RuleIntent(kind: .deviceOffline, device: "the printer")
        #expect(mac(intent) == .pickDevice([printer, laserJet]))
        guard case let .alert(draft) = mac(intent, chosen: laserJet) else { Issue.record("not an alert")
        return
        }
        #expect(draft.rule.conditions.deviceID == laserJet.id)
    }

    @Test func noMatchingDeviceOrNoDeviceGivesAClearMessage() {
        #expect(mac(RuleIntent(kind: .deviceOffline, device: "the garage door"))
            == .message("No device on this network matches “the garage door”."))
        #expect(mac(RuleIntent(kind: .deviceOffline)) == .message("Say which device, for example “the NAS”."))
    }

    @Test func unsupportedGivesWhatTheAppCanDo() {
        #expect(mac(.unsupported) == .message(
            "I can create alerts for a device going offline, coming online, new devices, or high latency, and port-scan presets."
        ))
    }

    // MARK: - Duration notes (macOS)

    @Test func anOfflineDurationIsTimedByAMonitoringTarget() {
        guard case let .alert(draft) = mac(RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 300)) else {
            Issue.record("not an alert")
            return
        }
        #expect(draft.notes(addingTarget: true, timing: timing) == [
            "Fires once Synology DS920 has been unreachable for 5 minutes, timed by its monitoring target, which checks it every 5 seconds."
        ])
    }

    @Test func withoutATargetTheNoteSaysScansAreSlowerThanTheDuration() {
        guard case let .alert(draft) = mac(RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 300)) else {
            Issue.record("not an alert")
            return
        }
        #expect(draft.notes(addingTarget: false, timing: timing) == [
            "Without a monitoring target only scans check Synology DS920. A scan reports a device offline after 3 missed scans "
                + "and at least 15 minutes, so this alert comes then, not at 5 minutes."
        ])
    }

    @Test func aDurationLongerThanTheScanGraceNeedsATarget() {
        guard case let .alert(draft) = mac(RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 3600)) else {
            Issue.record("not an alert")
            return
        }
        #expect(draft.notes(addingTarget: false, timing: timing) == [
            "Without a monitoring target only scans check Synology DS920, and a scan reports it offline once, after 3 missed scans "
                + "and at least 15 minutes. This alert fires only if it has been unreachable for 1 hour by then; "
                + "add the monitoring target to time it."
        ])
    }

    @Test func latencyWithoutATargetNeverFiresAndSaysSo() {
        guard case let .alert(draft) = mac(RuleIntent(kind: .latencyAbove, device: "NAS", thresholdMilliseconds: 250, durationSeconds: 120)) else {
            Issue.record("not an alert")
            return
        }
        #expect(draft.notes(addingTarget: false, timing: timing) == [
            "Only monitoring targets measure latency, so without one this rule never fires."
        ])
        #expect(draft.notes(addingTarget: true, timing: timing) == [
            "Fires when Synology DS920's latency stays above 250 ms for 2 minutes, measured by its monitoring target every 5 seconds."
        ])
    }

    @Test func theNotesFollowAnEditedRule() {
        guard case var .alert(draft) = mac(RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 300)) else {
            Issue.record("not an alert")
            return
        }
        draft.rule.minimumDuration = nil
        #expect(draft.notes(addingTarget: true, timing: timing).isEmpty)
    }

    // MARK: - iOS

    @Test func onIOSAnOfflineRuleBecomesAMonitoringTargetDraftThatSaysWhatItCantTime() {
        let outcome = iOS(RuleIntent(kind: .deviceOffline, device: "NAS", durationSeconds: 300))
        #expect(outcome == .target(TargetDraft(name: "Synology DS920", host: "10.0.0.50", deviceID: nas.id, notes: [
            "The app checks monitoring targets during background refresh, when iOS allows it, and reports one down after 3 failed checks. "
                + "It can't time 5 minutes.",
            Self.portNote
        ])))
    }

    @Test func onIOSALatencyThresholdIsNotSavedWithTheTargetAndSaysSo() {
        guard case let .target(draft) = iOS(RuleIntent(kind: .latencyAbove, device: "NAS", thresholdMilliseconds: 250)) else {
            Issue.record("not a target")
            return
        }
        #expect(draft.notes == [
            "High-latency alerts use one threshold for every target (Settings › Notifications), so 250 ms isn't saved with this target.",
            Self.portNote
        ])
    }

    @Test func onIOSOtherAlertsAreOnTheMac() {
        let message = PlainRuleOutcome.message("Alerts for a device coming online or for new devices are available in the Mac app.")
        #expect(iOS(RuleIntent(kind: .newDevice)) == message)
        #expect(iOS(RuleIntent(kind: .deviceOnline, device: "NAS")) == message)
    }

    @Test func onIOSAnExistingTargetIsNotAddedAgain() {
        #expect(iOS(RuleIntent(kind: .deviceOffline, device: "NAS"), targetHosts: ["10.0.0.50"])
            == .message("A monitoring target for Synology DS920 already exists."))
    }

    @Test func onIOSThePortScanPresetWorksToo() {
        #expect(iOS(RuleIntent(kind: .portScan, device: "LaserJet", portPreset: .web)) == .portScan(device: laserJet, preset: .web))
    }
}

@Suite("Plain-English rules: composer (#450)")
@MainActor
struct PlainRuleComposerTests {
    private let printer = RuleDevice(id: UUID(), displayName: "Office Printer", deviceType: .printer, maker: nil, ipAddress: "10.0.0.40")
    private let laserJet = RuleDevice(id: UUID(), displayName: "LaserJet", deviceType: .printer, maker: nil, ipAddress: "10.0.0.41")
    private let timing = RuleTiming(targetCheckInterval: 5)

    private func composer(_ answers: [String: RuleIntent] = [:]) -> PlainRuleComposer {
        PlainRuleComposer(parser: FixedRuleIntentParser(answers: answers), platform: .mac)
    }

    @Test func anUnreadableAnswerGivesTheMessage() async {
        let composer = composer()
        await composer.submit("what's the weather", devices: [printer], timing: timing, targetHosts: [])
        #expect(composer.outcome == .message(RuleIntent.unsupportedMessage))
    }

    @Test func aModelFailureGivesTheMessageToo() async {
        let composer = PlainRuleComposer(parser: UnavailableRuleIntentParser(), platform: .mac)
        await composer.submit("anything", devices: [printer], timing: timing, targetHosts: [])
        #expect(composer.outcome == .message(RuleIntent.unsupportedMessage))
    }

    @Test func pickingADeviceTurnsThePickerIntoADraft() async {
        let composer = composer(["printer down": RuleIntent(kind: .deviceOffline, device: "printer")])
        await composer.submit("printer down", devices: [printer, laserJet], timing: timing, targetHosts: [])
        #expect(composer.outcome == .pickDevice([printer, laserJet]))
        composer.choose(laserJet)
        guard case let .alert(draft) = composer.outcome else { Issue.record("no draft")
        return
        }
        #expect(draft.rule.conditions.deviceID == laserJet.id)
    }

    @Test func nothingIsAskedDuringAScan() async {
        let composer = composer(["printer down": RuleIntent(kind: .deviceOffline, device: "printer")])
        await composer.submit("printer down", devices: [printer], timing: timing, targetHosts: [], isScanning: true)
        #expect(composer.outcome == .message("Wait for the scan to finish, then try again."))
    }

    /// Return submits even while a request runs; an empty or mid-scan submit must not leave the
    /// field stuck "working" with Create Draft disabled.
    @Test func aSubmitThatEndsEarlyClearsWorking() async {
        let parser = HeldParser()
        let composer = PlainRuleComposer(parser: parser, platform: .mac)
        let first = Task { await composer.submit("printer down", devices: [printer], timing: timing, targetHosts: []) }
        await parser.waitUntilAsked()
        #expect(composer.isWorking)
        await composer.submit("  ", devices: [printer], timing: timing, targetHosts: [])
        #expect(!composer.isWorking)

        let second = Task { await composer.submit("printer down", devices: [printer], timing: timing, targetHosts: []) }
        await parser.waitUntilAsked(count: 2)
        await composer.submit("printer down", devices: [printer], timing: timing, targetHosts: [], isScanning: true)
        #expect(!composer.isWorking)
        #expect(composer.outcome == .message("Wait for the scan to finish, then try again."))

        await parser.release()
        await first.value
        await second.value
        #expect(!composer.isWorking)
        #expect(composer.outcome == .message("Wait for the scan to finish, then try again."), "Superseded answers are dropped")
    }

    @Test func blankInputAsksNothingAndClearHidesTheDraft() async {
        let composer = composer(["printer down": RuleIntent(kind: .deviceOffline, device: "printer")])
        await composer.submit("   ", devices: [printer], timing: timing, targetHosts: [])
        #expect(composer.outcome == nil)
        await composer.submit("printer down", devices: [printer], timing: timing, targetHosts: [])
        #expect(composer.outcome != nil)
        composer.clear()
        #expect(composer.outcome == nil)
    }
}

/// Holds every parse until released.
private actor HeldParser: RuleIntentParsing {
    private var asked = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    nonisolated var isAvailable: Bool { true }

    func parse(_ text: String) async -> RuleIntent? {
        asked += 1
        await withCheckedContinuation { waiting.append($0) }
        return RuleIntent(kind: .deviceOffline, device: "printer")
    }

    func waitUntilAsked(count: Int = 1) async {
        while asked < count {
            await Task.yield()
        }
    }

    func release() {
        waiting.forEach { $0.resume() }
        waiting = []
    }
}
