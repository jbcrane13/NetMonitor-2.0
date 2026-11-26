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
        ("DSL", .broadband), ("VDSL", .broadband), ("Broadband", .broadband), ("WAN", .broadband),
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
        #expect(ModemLightKind(label: "WAN") == .broadband)
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
        ("POWER", .off, .problem, "Power light is off: the modem has no power. Check its power cable and outlet."),
        ("DSL", .green, .normal, "Broadband light is green: the line from your provider is connected."),
        ("DSL", .off, .problem, "Broadband light is off: the modem has no line from your provider. Check the cable to the wall socket."),
        ("INTERNET", .green, .normal, "Internet light is green: the modem is connected to the internet."),
        ("INTERNET", .amber, .attention, "Internet light is amber: on many modems this means it reaches your provider but isn't online."),
        ("LAN 2", .off, .note, "Ethernet 2 light is off: nothing is connected to that port, or the connected device is off."),
        ("LAN 4", .amber, .attention, "Ethernet 4 light is amber: on many modems this means a device is connected at a slower speed."),
        ("WLAN 5G", .off, .note, "Wi-Fi light is off: Wi-Fi is turned off on this unit. That is expected if you use a separate router."),
        ("US", .red, .problem, "Upstream light is red: the modem has no upstream connection to your provider."),
        ("DS", .blue, .normal, "Downstream light is blue: the modem is connected to your provider's downstream channels.")
    ])
    func meanings(label: String, color: ModemLightColor, severity: ModemLightSeverity, text: String) throws {
        let meaning = try #require(ModemLightVerdict(label: label, color: color).meaning)
        #expect(meaning.severity == severity)
        #expect(meaning.text == text)
    }

    @Test("An unknown label or an unclear colour is shown as read, without a verdict")
    func noVerdict() {
        #expect(ModemLightVerdict(label: "USB", color: .green).meaning == nil)
        #expect(ModemLightVerdict(label: "INTERNET", color: .unknown).meaning == nil)
        #expect(ModemLightVerdict(label: "USB", color: .green).reading == "USB: green")
        #expect(ModemLightVerdict(label: "INTERNET", color: .unknown).reading == "INTERNET: colour not clear")
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
            "Ethernet 2 light is off: nothing is connected to that port, or the connected device is off.",
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
        #expect(dark.verdicts[0].meaning?.severity == .problem)
        #expect(dark.verdicts[0].note == nil)
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
            .init(label: "POWER", color: .green), .init(label: "USB", color: .white), .init(label: "INTERNET", color: .red)
        ]))
        let request = try #require(report.insightRequest)
        #expect(request.subject == "Modem status lights read from a photo")
        #expect(request.observations == [
            "Internet light is red: the modem has no internet connection.",
            "Power light is green: the modem has power."
        ])
        #expect(request.facts == [
            "Light labelled POWER: green",
            "Light labelled USB: white",
            "Light labelled INTERNET: red",
            "Whether a light is blinking can't be seen in one photo"
        ])
    }

    @Test("Without a problem the summary line says so; with one it names how many")
    func headline() {
        let fine = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [.init(label: "POWER", color: .green)]))
        #expect(fine.headline == "No light shows a problem.")
        let bad = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "INTERNET", color: .red), .init(label: "DSL", color: .off), .init(label: "LAN 1", color: .amber)
        ]))
        #expect(bad.headline == "2 lights show a problem.")
        let odd = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [.init(label: "LAN 1", color: .amber)]))
        #expect(odd.headline == "1 light needs a look.")
        let unclear = ModemPanelReport(answer: ModemPanelAnswer(status: .panel, lights: [
            .init(label: "POWER", color: .green), .init(label: "ONLINE", color: .unknown)
        ]))
        #expect(unclear.headline == "No light shows a problem. 1 known light wasn't clear in the photo.")
    }
}
