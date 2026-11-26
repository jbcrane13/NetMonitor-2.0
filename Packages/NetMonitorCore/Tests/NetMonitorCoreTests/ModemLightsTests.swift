import Foundation
import Testing
@testable import NetMonitorCore

/// #558: the app's reading of a modem's status lights. The model only names each light's label
/// and colour; everything here is the app's own table. The real model is never called.
@Suite("Modem lights")
struct ModemLightsTests {
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
        "USB", "WLAN-WPS", "WPS", "LINK", "ADSL ERROR", "Internet Explorer", "DSLAM", "LANE", "Status", ""
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

    // MARK: - On or off

    @Test("A colour is lit, off is unlit, and an unclear colour is undetermined")
    func onOffFromColour() {
        for color in [ModemLightColor.green, .amber, .red, .blue, .white] {
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
        #expect(ModemLightColor(modelValue: "purple") == .unknown)
    }

    // MARK: - Meanings

    @Test("A red Internet light means no internet connection, and is a problem")
    func redInternet() throws {
        let verdict = ModemLightVerdict(label: "INTERNET", color: .red)
        let meaning = try #require(verdict.meaning)
        #expect(meaning.severity == .problem)
        #expect(meaning.text == "Internet light is red: the modem has no internet connection.")
    }

    @Test("Literal meanings for the common lights", arguments: [
        ("POWER", ModemLightColor.green, ModemLightSeverity.normal, "Power light is green: the modem has power."),
        ("POWER", .off, .attention, "Power reads as off. If it is dark, the modem has no power: check its power cable and outlet."),
        ("DSL", .green, .normal, "Broadband light is green: the line from your provider is connected."),
        ("DSL", .off, .attention,
         "Broadband reads as off. If it is dark, the modem has no line from your provider: check the cable to the wall socket."),
        ("INTERNET", .off, .attention, "Internet reads as off. If it is dark, the modem isn't online."),
        ("INTERNET", .green, .normal, "Internet light is green: the modem is connected to the internet."),
        ("INTERNET", .amber, .attention, "Internet light is amber: on many modems this means it reaches your provider but isn't online."),
        ("LAN 2", .off, .note, "Ethernet 2 reads as off. If it is dark, nothing is connected to that port, or the connected device is off."),
        ("LAN 4", .amber, .attention, "Ethernet 4 light is amber: on many modems this means a device is connected at a slower speed."),
        ("WLAN", .off, .note, "Wi-Fi reads as off. If it is dark, Wi-Fi is turned off on this unit. That is expected if you use a separate router."),
        ("WAN", .green, .normal,
         "WAN light is green: the router has a link to the modem or provider. That alone doesn't show the internet is working."),
        ("WAN", .off, .attention, "WAN reads as off. If it is dark, nothing is connected to the WAN port, or the modem it connects to is off."),
        ("WLAN 2.4G", .green, .normal, "Wi-Fi 2.4G light is green: that Wi-Fi band is on."),
        ("WLAN 5G", .off, .note, "Wi-Fi 5G reads as off. If it is dark, that Wi-Fi band is turned off on this unit."),
        ("WiFi 5 GHz", .off, .note, "Wi-Fi 5GHZ reads as off. If it is dark, that Wi-Fi band is turned off on this unit."),
        ("US", .off, .attention, "Upstream reads as off. If it is dark, the modem has no upstream connection to your provider."),
        ("PHONE", .off, .note, "Phone reads as off. If it is dark, phone service is off or not set up. That is expected if you don't use it."),
        ("US", .red, .problem, "Upstream light is red: the modem has no upstream connection to your provider."),
        ("DS", .blue, .normal, "Downstream light is blue: the modem is connected to your provider's downstream channels.")
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
        let report = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "POWER", color: .green),
            .init(label: "USB", color: .green),
            .init(label: "LAN 2", color: .off),
            .init(label: "INTERNET", color: .red)
        ]))
        #expect(report.isPanel)
        #expect(report.keyPoints == [
            "Internet light is red: the modem has no internet connection.",
            "Ethernet 2 reads as off. If it is dark, nothing is connected to that port, or the connected device is off.",
            "Power light is green: the modem has power."
        ])
        #expect(report.worst == .problem)
        #expect(report.verdicts.map(\.label) == ["POWER", "USB", "LAN 2", "INTERNET"])
    }

    @Test("A power light read as off while other lights are lit gets no verdict")
    func powerOffContradiction() {
        // Real-model probe, white case: a lit white POWER light was read as off.
        let report = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "POWER", color: .off), .init(label: "DS", color: .blue)
        ]))
        #expect(report.verdicts[0].meaning == nil)
        #expect(report.verdicts[0].note == "Other lights are lit, so this light may not show clearly in the photo.")
        #expect(report.keyPoints == ["Downstream light is blue: the modem is connected to your provider's downstream channels."])
        let dark = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "POWER", color: .off), .init(label: "DSL", color: .off)
        ]))
        #expect(dark.verdicts[0].meaning?.severity == .attention)
        #expect(dark.verdicts[0].note == nil)
        // The model is told the colour isn't clear, not the reading the app distrusts.
        #expect(report.insightRequest?.facts.first == "Light labelled POWER: colour not clear")
    }

    @Test("Unsupported ignores every light the model filled in anyway")
    func unsupported() {
        let report = ModemPanelReport(answer: ModemPanelAnswer(status: .unsupported, lights: [.init(label: "POWER", color: .green)]))
        #expect(!report.isPanel)
        #expect(report.verdicts.isEmpty)
        #expect(report.keyPoints.isEmpty)
        #expect(report.insightRequest == nil)
    }

    @Test("A panel with no lights read is not a reading")
    func noLights() {
        let report = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [.init(label: "  ", color: .green)]))
        #expect(!report.isPanel)
        #expect(report.insightRequest == nil)
    }

    @Test("Labels are model output: flattened, capped and at most 16 lights")
    func labelHygiene() {
        let long = String(repeating: "X", count: 60)
        let lights = [ModemLightReading(label: "INTER\nNET", color: .red), .init(label: long, color: .green)]
            + (0 ..< 20).map { ModemLightReading(label: "LAN \($0)", color: .green) }
        let report = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: lights))
        #expect(report.verdicts.count == 16)
        #expect(report.verdicts[0].label == "INTER NET")
        #expect(report.verdicts[1].label.count == ModemPanelReport.labelLimit)
    }

    @Test("The model is given the key points and every light as read")
    func insightRequest() throws {
        let report = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "POWER", color: .green), .init(label: "USB", color: .white), .init(label: "INTERNET", color: .red),
            .init(label: "LAN 2", color: .off)
        ]))
        let request = try #require(report.insightRequest)
        #expect(request.subject == "Modem status lights read from a photo")
        #expect(request.observations == [
            "Internet light is red: the modem has no internet connection.",
            "Ethernet 2 reads as off. If it is dark, nothing is connected to that port, or the connected device is off.",
            "Power light is green: the modem has power."
        ])
        // An off reading goes to the model as one to check, so the wording can't assert a fault.
        #expect(request.facts == [
            "Light labelled POWER: green",
            "Light labelled USB: white",
            "Light labelled INTERNET: red",
            "Light labelled LAN 2: reads as off (check)",
            "Whether a light is blinking can't be seen in one photo"
        ])
    }

    @Test("While a light needs a check the model words nothing: in the probe it turned 'reads as off (check)' into a fault")
    func noWordingWithChecks() {
        let report = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "POWER", color: .green), .init(label: "INTERNET", color: .off)
        ]))
        #expect(report.isPanel)
        #expect(report.keyPoints.first == "Internet reads as off. If it is dark, the modem isn't online.")
        #expect(report.insightRequest == nil)
    }

    @Test("Without a problem the summary line says so; with one it names how many")
    func headline() {
        let fine = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [.init(label: "POWER", color: .green)]))
        #expect(fine.headline == "No light shows a problem.")
        let bad = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "INTERNET", color: .red), .init(label: "DSL", color: .off), .init(label: "LAN 1", color: .amber)
        ]))
        // Off lights are counted as lights to check, never as problems.
        #expect(bad.headline == "1 light shows a problem. 1 light reads as off: check it.")
        let offOnly = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "POWER", color: .off), .init(label: "DSL", color: .off),
            .init(label: "INTERNET", color: .off), .init(label: "LAN 1", color: .off)
        ]))
        #expect(offOnly.headline == "No light shows a problem. 3 lights read as off: check them.")
        #expect(offOnly.worst == .attention)
        let odd = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [.init(label: "LAN 1", color: .amber)]))
        #expect(odd.headline == "1 light needs a look.")
        let unclear = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "POWER", color: .green), .init(label: "ONLINE", color: .unknown)
        ]))
        #expect(unclear.headline == "No light shows a problem. 1 known light wasn't clear in the photo.")
    }
}
