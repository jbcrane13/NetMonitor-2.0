import Foundation
import Testing
@testable import NetMonitorCore

/// #558: the app's reading of a modem's status lights. The model only names each light's label
/// and colour; every line the user sees is the app's own text. The real model is never called.
@Suite("Modem lights")
struct ModemLightsTests {
    private func report(_ lights: [(String, ModemLightColor)]) -> ModemPanelReport {
        ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: lights.map { ModemLightReading(label: $0.0, color: $0.1) }))
    }

    // MARK: - Labels

    @Test("Printed labels map to the app's light kinds", arguments: [
        ("POWER", ModemLightKind.power), ("Pwr", .power),
        ("DSL", .broadband), ("VDSL", .broadband), ("Broadband", .broadband), ("WAN", .wan),
        ("INTERNET", .internet), ("Online", .internet),
        ("WLAN", .wifi), ("Wi-Fi", .wifi), ("WiFi 2.4G", .wifi), ("WLAN 5GHz", .wifi), ("Wireless", .wifi),
        ("LAN", .ethernet), ("LAN 1", .ethernet), ("ETHERNET", .ethernet), ("ETH2", .ethernet),
        ("PHONE", .phone), ("Tel 1", .phone), ("VoIP", .phone),
        ("US", .upstream), ("Upstream", .upstream), ("DS", .downstream), ("Downstream", .downstream)
    ])
    func knownLabels(label: String, kind: ModemLightKind) {
        #expect(ModemLightKind(label: label) == kind)
    }

    @Test("Labels that only contain a known word are not that light", arguments: [
        "USB", "WLAN-WPS", "WPS", "LINK", "ADSL ERROR", "Internet Explorer", "DSLAM", "LANE", "Status", "2.4G", ""
    ])
    func unknownLabels(label: String) {
        // USB is not US, DSL is not DS, WLAN is not LAN, WAN is not WLAN: whole words only.
        #expect(ModemLightKind(label: label) == nil)
    }

    @Test("WLAN is Wi-Fi, not Ethernet; DSL is broadband, not downstream")
    func confusablePairs() {
        #expect(ModemLightKind(label: "WLAN") == .wifi)
        #expect(ModemLightKind(label: "LAN") == .ethernet)
        #expect(ModemLightKind(label: "WAN") == .wan)
        #expect(ModemLightKind(label: "DSL") == .broadband)
        #expect(ModemLightKind(label: "DS") == .downstream)
        #expect(ModemLightKind(label: "US") == .upstream)
    }

    // MARK: - Colours

    @Test("A colour is lit, off is unlit, and an unclear colour is undetermined")
    func onOffFromColour() {
        for color in [ModemLightColor.green, .amber, .red, .blue, .white, .purple] {
            #expect(color.isLit == true)
        }
        #expect(ModemLightColor.off.isLit == false)
        #expect(ModemLightColor.unknown.isLit == nil)
    }

    @Test("The model's colour words map to the closed set; anything else is unknown")
    func colourWords() {
        #expect(ModemLightColor(modelValue: "green") == .green)
        #expect(ModemLightColor(modelValue: "Amber") == .amber)
        #expect(ModemLightColor(modelValue: "orange") == .amber)
        #expect(ModemLightColor(modelValue: "unlit") == .off)
        #expect(ModemLightColor(modelValue: "magenta") == .purple)
        #expect(ModemLightColor(modelValue: "teal") == .unknown)
    }

    @Test("Purple is shown as read and has no meaning in the table")
    func purpleAsRead() {
        let verdict = ModemLightVerdict(label: "INTERNET", color: .purple)
        #expect(verdict.reading == "INTERNET: purple")
        #expect(verdict.meaning == nil)
    }

    // MARK: - Meanings

    @Test("Hedged meanings: lit lines say what the light normally means, red is stated as read", arguments: [
        ("POWER", ModemLightColor.green, ModemLightSeverity.normal, "Power light is green: this normally means the modem has power."),
        ("POWER", .red, .problem, "Power light reads as red: this normally means a hardware fault or a failed start-up."),
        ("POWER", .off, .attention, "Power reads as off. If it is dark, the modem has no power: check its power cable and outlet."),
        ("DSL", .green, .normal, "Broadband light is green: this normally means the line from your provider is connected."),
        ("DSL", .off, .attention,
         "Broadband reads as off. If it is dark, the modem has no line from your provider: check the cable to the wall socket."),
        ("INTERNET", .green, .normal, "Internet light is green: this normally means the modem is online."),
        ("INTERNET", .red, .problem, "Internet light reads as red: this normally means the modem has no internet connection."),
        ("INTERNET", .amber, .attention, "Internet light is amber: on many modems this means it reaches your provider but isn't online."),
        ("INTERNET", .off, .attention, "Internet reads as off. If it is dark, the modem isn't online."),
        ("LAN 2", .off, .note, "Ethernet 2 reads as off. If it is dark, nothing is connected to that port, or the connected device is off."),
        ("LAN 4", .amber, .attention, "Ethernet 4 light is amber: on many modems this means a device is connected at a slower speed."),
        ("WLAN", .off, .note, "Wi-Fi reads as off. If it is dark, Wi-Fi is turned off on this unit. That is expected if you use a separate router."),
        ("WAN", .green, .normal,
         "WAN light is green: this normally means the router has a link to the modem or provider. That alone doesn't show the internet is working."),
        ("WAN", .off, .attention, "WAN reads as off. If it is dark, nothing is connected to the WAN port, or the modem it connects to is off."),
        ("WLAN 2.4G", .green, .normal, "Wi-Fi 2.4G light is green: this normally means that Wi-Fi band is on."),
        ("WLAN 5G", .off, .note, "Wi-Fi 5G reads as off. If it is dark, that Wi-Fi band is turned off on this unit."),
        ("US", .red, .problem, "Upstream light reads as red: this normally means the modem has no upstream connection to your provider."),
        ("US", .off, .attention, "Upstream reads as off. If it is dark, the modem has no upstream connection to your provider."),
        ("DS", .blue, .normal, "Downstream light is blue: this normally means the modem is connected to your provider's downstream channels."),
        ("PHONE", .off, .note, "Phone reads as off. If it is dark, phone service is off or not set up. That is expected if you don't use it.")
    ])
    func meanings(label: String, color: ModemLightColor, severity: ModemLightSeverity, text: String) throws {
        let meaning = try #require(ModemLightVerdict(label: label, color: color).meaning)
        #expect(meaning.severity == severity)
        #expect(meaning.text == text)
    }

    @Test("Off is never a problem for any light: white lights on a light case read as off (real-model probe)")
    func offIsNeverAProblem() {
        for kind in ModemLightKind.allCases {
            let label = kind == .wifi ? "WLAN" : kind == .broadband ? "DSL" : kind.name.uppercased()
            let meaning = ModemLightVerdict(label: label, color: .off).meaning
            #expect(meaning != nil, "\(label)")
            #expect(meaning.map { $0.severity < .problem } == true, "\(label)")
            #expect(meaning?.readsAsOff == true, "\(label)")
        }
        #expect(ModemLightVerdict(label: "INTERNET", color: .red).meaning?.readsAsOff == false)
    }

    @Test("An unknown label or an unclear colour is shown as read, without a verdict")
    func noVerdict() {
        #expect(ModemLightVerdict(label: "USB", color: .green).meaning == nil)
        #expect(ModemLightVerdict(label: "INTERNET", color: .unknown).meaning == nil)
        #expect(ModemLightVerdict(label: "USB", color: .green).reading == "USB: green")
        #expect(ModemLightVerdict(label: "INTERNET", color: .unknown).reading == "INTERNET: colour not clear")
        #expect(ModemLightVerdict(label: "INTERNET", color: .off).reading == "INTERNET: reads as off")
    }

    // MARK: - Report

    @Test("Problems come first in the key points; unknown lights stay out of them")
    func keyPointOrder() {
        let report = report([("POWER", .green), ("USB", .green), ("LAN 2", .off), ("INTERNET", .red)])
        #expect(report.isPanel)
        #expect(report.keyPoints == [
            "Internet light reads as red: this normally means the modem has no internet connection.",
            "Ethernet 2 reads as off. If it is dark, nothing is connected to that port, or the connected device is off.",
            "Power light is green: this normally means the modem has power."
        ])
        #expect(report.worst == .problem)
        #expect(report.verdicts.map(\.label) == ["POWER", "USB", "LAN 2", "INTERNET"])
    }

    @Test("A power light read as off while other lights are lit is shown as colour not clear")
    func powerOffContradiction() {
        // Real-model probe, white case: a lit white POWER light was read as off.
        let report = report([("POWER", .off), ("DS", .blue)])
        #expect(report.verdicts[0].meaning == nil)
        #expect(report.verdicts[0].reading == "POWER: colour not clear")
        #expect(report.verdicts[0].note == "Other lights are lit, so this light may not show clearly in the photo.")
        #expect(report.headline == "No light shows a problem. 1 known light wasn't clear in the photo.")
        let dark = self.report([("POWER", .off), ("DSL", .off)])
        #expect(dark.verdicts[0].meaning?.severity == .attention)
        #expect(dark.verdicts[0].note == nil)
    }

    @Test("Unsupported ignores every light the model filled in anyway")
    func unsupported() {
        let report = ModemPanelReport(answer: ModemPanelAnswer(status: .unsupported, lights: [.init(label: "POWER", color: .green)]))
        #expect(!report.isPanel)
        #expect(report.verdicts.isEmpty)
        #expect(report.keyPoints.isEmpty)
    }

    @Test("A panel with no lights read is not a reading")
    func noLights() {
        #expect(!report([("  ", .green)]).isPanel)
    }

    @Test("Labels are model output: flattened and capped")
    func labelHygiene() {
        let long = String(repeating: "X", count: 60)
        let report = report([("INTER\nNET", .red), (long, .green)])
        #expect(report.verdicts[0].label == "INTER NET")
        #expect(report.verdicts[1].label.count == ModemPanelReport.labelLimit)
    }

    @Test("More than 16 lights: the first 16 are kept and the reading says it is partial")
    func partialReading() {
        let full = report((0 ..< 16).map { ("LAN \($0)", .green) })
        #expect(full.verdicts.count == 16)
        #expect(full.notices.isEmpty)
        let more = report((0 ..< 17).map { ("LAN \($0)", .green) })
        #expect(more.verdicts.count == 16)
        #expect(more.notices == ["The photo shows more lights than the app reads at once. Only the first 16 are listed."])
    }

    @Test("Two power lights: the photo may show more than one device")
    func severalDevices() {
        let report = report([("POWER", .green), ("INTERNET", .green), ("POWER", .green), ("DSL", .green)])
        #expect(report.notices == ["This photo may show more than one device."])
        #expect(self.report([("POWER", .green), ("INTERNET", .green)]).notices.isEmpty)
    }

    // MARK: - Headline

    @Test("Without a problem the summary line says so; with one it names how many")
    func headline() {
        #expect(report([("POWER", .green)]).headline == "No light shows a problem.")
        #expect(report([("INTERNET", .red), ("DSL", .off), ("LAN 1", .amber)]).headline
            == "1 light shows a problem. 1 light reads as off: check it. 1 light needs a look.")
        #expect(report([("LAN 1", .amber)]).headline == "1 light needs a look.")
        #expect(report([("POWER", .green), ("ONLINE", .unknown)]).headline
            == "No light shows a problem. 1 known light wasn't clear in the photo.")
    }

    @Test("Off lights lead the headline; no all-clear while any light reads as off")
    func darkPanel() {
        #expect(report([("POWER", .off), ("DSL", .off), ("INTERNET", .off), ("LAN 1", .off)]).headline
            == "4 lights read as off: check them.")
        #expect(report([("POWER", .green), ("INTERNET", .green), ("LAN 2", .off)]).headline
            == "1 light reads as off: check it.")
    }

    @Test("An unknown red light is named, never hidden behind an all-clear")
    func unknownRed() {
        #expect(report([("POWER", .green), ("PON", .green), ("LOS", .red)]).headline
            == "1 light is red: LOS. The app doesn't know this light; check your modem's guide.")
        #expect(report([("POWER", .green), ("SERVICE", .red)]).headline
            == "1 light is red: SERVICE. The app doesn't know this light; check your modem's guide.")
        #expect(report([("POWER", .green), ("ALARM", .red), ("2.4G", .amber)]).headline
            == "2 lights are red or amber: ALARM, 2.4G. The app doesn't know these lights; check your modem's guide.")
        #expect(report([("POWER", .green), ("2.4G", .amber)]).headline
            == "1 light is amber: 2.4G. The app doesn't know this light; check your modem's guide.")
        // A green unknown light is shown as read; it doesn't stop the all-clear.
        #expect(report([("POWER", .green), ("USB", .green)]).headline == "No light shows a problem.")
    }
}
