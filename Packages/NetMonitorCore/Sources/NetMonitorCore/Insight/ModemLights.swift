import Foundation

// MARK: - What the model reads

/// A status light's colour, from a closed set (#558). The model names the colour; whether the
/// light is on is derived here: in the #447 spike it got every colour right but 4 of 8 on/off
/// answers wrong.
public enum ModemLightColor: String, Sendable, CaseIterable {
    case green, amber, red, blue, white
    /// Dark or unlit.
    case off
    /// The model couldn't tell.
    case unknown

    /// True for a colour, false for off, nil when the colour isn't clear.
    public var isLit: Bool? {
        switch self {
        case .green, .amber, .red, .blue, .white: true
        case .off: false
        case .unknown: nil
        }
    }

    /// The words the model may answer with, `unknown` first.
    public static let modelValues = ["unknown", "off", "green", "amber", "orange", "yellow", "red", "blue", "white"]

    /// The colour for one of the model's words; anything outside the set is unknown.
    public init(modelValue: String) {
        switch modelValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "green": self = .green
        case "amber", "orange", "yellow": self = .amber
        case "red": self = .red
        case "blue": self = .blue
        case "white": self = .white
        case "off", "unlit", "dark": self = .off
        default: self = .unknown
        }
    }

    /// The colour as a word in a sentence.
    var word: String {
        self == .unknown ? "colour not clear" : rawValue
    }
}

/// One light as the model read it: its printed label and its colour. The label is model output.
public struct ModemLightReading: Sendable, Equatable {
    public var label: String
    public var color: ModemLightColor

    public init(label: String, color: ModemLightColor) {
        self.label = label
        self.color = color
    }
}

/// The model's answer for a photo (#558).
public struct ModemPanelAnswer: Sendable, Equatable {
    public enum Status: String, Sendable, CaseIterable {
        /// The photo isn't of a modem's or router's status lights; the lights are ignored.
        case unsupported
        case panel
    }

    public var status: Status
    public var lights: [ModemLightReading]

    public init(status: Status, lights: [ModemLightReading]) {
        self.status = status
        self.lights = lights
    }
}

// MARK: - The app's table

/// The lights the app knows the meaning of (#558), found from the printed label.
public enum ModemLightKind: String, Sendable, CaseIterable {
    case power, broadband, internet, wifi, ethernet, phone, upstream, downstream
    /// A router's WAN port: its link to the modem or provider, which can stay up in an outage.
    case wan

    /// The light's name in the app's sentences.
    public var name: String {
        switch self {
        case .power: "Power"
        case .broadband: "Broadband"
        case .internet: "Internet"
        case .wifi: "Wi-Fi"
        case .ethernet: "Ethernet"
        case .phone: "Phone"
        case .upstream: "Upstream"
        case .downstream: "Downstream"
        case .wan: "WAN"
        }
    }

    /// Printed labels for each kind, as whole words. A label matches when it is one of these,
    /// optionally followed by a port number or a Wi-Fi band: `LAN 2`, `ETH2`, `WiFi 2.4G`.
    private static let synonyms: [(words: [String], kind: ModemLightKind)] = [
        (["POWER"], .power), (["PWR"], .power),
        (["DSL"], .broadband), (["ADSL"], .broadband), (["VDSL"], .broadband), (["BROADBAND"], .broadband),
        (["SYNC"], .broadband), (["WAN"], .wan),
        (["INTERNET"], .internet), (["ONLINE"], .internet),
        (["WLAN"], .wifi), (["WIFI"], .wifi), (["WI", "FI"], .wifi), (["WIRELESS"], .wifi),
        (["LAN"], .ethernet), (["ETHERNET"], .ethernet), (["ETH"], .ethernet),
        (["PHONE"], .phone), (["TEL"], .phone), (["VOIP"], .phone),
        (["US"], .upstream), (["UPSTREAM"], .upstream),
        (["DS"], .downstream), (["DOWNSTREAM"], .downstream)
    ]

    /// The kind `label` names, or nil for a label the app doesn't know.
    public init?(label: String) {
        guard let match = Self.match(label) else { return nil }
        self = match.kind
    }

    /// The kind, and the port number (Ethernet, Phone) or Wi-Fi band printed after it, if any.
    static func match(_ label: String) -> (kind: ModemLightKind, qualifier: String?)? {
        let words = Self.words(label)
        for (synonym, kind) in synonyms where words.starts(with: synonym) {
            let rest = Array(words.dropFirst(synonym.count))
            guard rest.allSatisfy(isSuffix) else { continue }
            switch kind {
            case .ethernet, .phone:
                // Only a lone number is a port.
                return (kind, rest.count == 1 && rest[0].allSatisfy(\.isNumber) ? rest[0] : nil)
            case .wifi:
                // A band: `2`,`4G` → 2.4G; `5`,`GHZ` → 5GHZ.
                let band = rest.enumerated().map { index, word in index > 0 && word.first?.isNumber == true ? "." + word : word }.joined()
                return (kind, band.isEmpty ? nil : band)
            default:
                return (kind, nil)
            }
        }
        return nil
    }

    /// Uppercase words of letters and digits, with a trailing number split off a word (`ETH2`
    /// → `ETH`, `2`), so `LAN-2` and `LAN2` match like `LAN 2`.
    private static func words(_ label: String) -> [String] {
        let raw = label.uppercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber)) }.map(String.init)
        return raw.flatMap { word -> [String] in
            guard let first = word.firstIndex(where: \.isNumber), first != word.startIndex,
                  word[first...].allSatisfy(\.isNumber)
            else { return [word] }
            return [String(word[..<first]), String(word[first...])]
        }
    }

    /// A port number or a band after the light's name: `2`, `5G`, `4GHZ`, `GHZ`.
    private static func isSuffix(_ word: String) -> Bool {
        let digits = word.prefix { $0.isNumber }
        let unit = word.dropFirst(digits.count)
        return (!digits.isEmpty && ["", "G", "GHZ"].contains(unit)) || ["G", "GHZ"].contains(word)
    }
}

/// How much a light's state matters (#558), least first.
public enum ModemLightSeverity: Int, Sendable, Comparable, CaseIterable {
    /// Expected, nothing to do.
    case normal
    /// Worth knowing, often expected (an empty Ethernet port).
    case note
    /// Vendors differ; check the modem's guide.
    case attention
    /// Most modems mean a fault by this.
    case problem

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// What the app says about one light.
public struct ModemLightMeaning: Sendable, Equatable {
    public let severity: ModemLightSeverity
    public let text: String
}

/// One light as read, with the app's meaning when it knows the label and the colour (#558).
public struct ModemLightVerdict: Sendable, Equatable, Identifiable {
    public let id: Int
    /// As printed, from the model.
    public let label: String
    public let color: ModemLightColor
    public let kind: ModemLightKind?
    /// Nil for an unknown label or an unclear colour: shown as read, without a verdict.
    public let meaning: ModemLightMeaning?
    /// Why a light the app knows has no verdict, when the reading contradicts itself.
    public let note: String?

    static let powerContradiction = "Other lights are lit, so this light may not show clearly in the photo."

    /// - Parameter othersLit: Whether another light on the panel is lit. A power light read as off
    ///   then contradicts the panel: in the real-model probe a lit white light on a white case was
    ///   read as off. It is shown as read, without a verdict.
    public init(id: Int = 0, label: String, color: ModemLightColor, othersLit: Bool = false) {
        self.id = id
        self.label = label
        self.color = color
        let match = ModemLightKind.match(label)
        kind = match?.kind
        if match?.kind == .power, color == .off, othersLit {
            meaning = nil
            note = Self.powerContradiction
        } else {
            meaning = match.flatMap { Self.meaning(kind: $0.kind, qualifier: $0.qualifier, color: color) }
            note = nil
        }
    }

    /// The light as read: "USB: green", "INTERNET: colour not clear".
    public var reading: String {
        "\(label): \(color.word)"
    }

    /// The table. Amber, blue and white mean different things across makers, so those are
    /// worded "on many modems" and kept from `problem`.
    static func meaning(kind: ModemLightKind, qualifier: String?, color: ModemLightColor) -> ModemLightMeaning? {
        guard color != .unknown else { return nil }
        let name = kind.name + (qualifier.map { " " + $0 } ?? "")
        let lit = color == .green || color == .blue || color == .white
        let entry: (ModemLightSeverity, String)
        switch kind {
        case .power:
            entry = lit ? (.normal, "the modem has power.")
                : color == .amber ? (.attention, "on many modems this means it is starting up or has a fault.")
                : color == .red ? (.problem, "on most modems this means a hardware fault or a failed start-up.")
                : (.problem, "the modem has no power. Check its power cable and outlet.")
        case .broadband:
            entry = lit ? (.normal, "the line from your provider is connected.")
                : color == .amber ? (.attention, "on many modems this means the line is still connecting or is weak.")
                : color == .red ? (.problem, "the modem has no line from your provider.")
                : (.problem, "the modem has no line from your provider. Check the cable to the wall socket.")
        case .internet:
            entry = lit ? (.normal, "the modem is connected to the internet.")
                : color == .amber ? (.attention, "on many modems this means it reaches your provider but isn't online.")
                : color == .red ? (.problem, "the modem has no internet connection.")
                : (.problem, "on most modems this means it isn't online. It may still be starting up.")
        case .wifi where qualifier != nil:
            entry = lit ? (.normal, "that Wi-Fi band is on.")
                : color == .amber ? (.attention, "on many modems this means Wi-Fi is pairing a device (WPS) or has a fault.")
                : color == .red ? (.problem, "on most modems this means Wi-Fi has a fault.")
                : (.note, "that Wi-Fi band is turned off on this unit.")
        case .wifi:
            entry = lit ? (.normal, "Wi-Fi is on.")
                : color == .amber ? (.attention, "on many modems this means Wi-Fi is pairing a device (WPS) or has a fault.")
                : color == .red ? (.problem, "on most modems this means Wi-Fi has a fault.")
                : (.note, "Wi-Fi is turned off on this unit. That is expected if you use a separate router.")
        case .ethernet:
            entry = lit ? (.normal, "a device is connected to that port.")
                : color == .amber ? (.attention, "on many modems this means a device is connected at a slower speed.")
                : color == .red ? (.problem, "on many modems this means a fault on that port.")
                : (.note, "nothing is connected to that port, or the connected device is off.")
        case .phone:
            entry = lit ? (.normal, "phone service is ready.")
                : color == .off ? (.note, "phone service is off or not set up. That is expected if you don't use it.")
                : (.attention, "on many modems this means phone service has a problem.")
        case .wan:
            entry = lit ? (.normal, "the router has a link to the modem or provider. That alone doesn't show the internet is working.")
                : color == .amber ? (.attention, "on many routers this means the WAN link is up but the internet isn't.")
                : color == .red ? (.problem, "on most routers this means there is no internet connection on the WAN port.")
                : (.problem, "nothing is connected to the WAN port, or the modem it connects to is off.")
        case .upstream, .downstream:
            let direction = kind == .upstream ? "upstream" : "downstream"
            entry = lit ? (.normal, "the modem is connected to your provider's \(direction) channels.")
                : color == .amber ? (.attention, "on many modems this means it is still connecting, or connected on fewer channels.")
                : color == .red ? (.problem, "the modem has no \(direction) connection to your provider.")
                : (.problem, "the modem has no \(direction) connection to your provider. Check the coax cable.")
        }
        return ModemLightMeaning(severity: entry.0, text: "\(name) light is \(color.rawValue): \(entry.1)")
    }
}

// MARK: - Report

/// The app's reading of a photo of a modem's lights (#558): each light as read, the app's
/// meanings, and the request the model words them from. Pure.
public struct ModemPanelReport: Sendable, Equatable {
    /// Most lights kept, and the longest label.
    public static let lightLimit = 16
    public static let labelLimit = 24
    /// Shown under every reading, and given to the model as a fact.
    public static let blinkingNote = "Whether a light is blinking can't be seen in one photo"

    /// False when the model said the photo isn't a panel of status lights, or read none.
    public let isPanel: Bool
    public let verdicts: [ModemLightVerdict]

    public init(answer: ModemPanelAnswer) {
        guard answer.status == .panel else {
            isPanel = false
            verdicts = []
            return
        }
        let lights = answer.lights.compactMap { light -> ModemLightReading? in
            let label = InsightRequest.line(light.label, limit: .max)
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            guard !label.isEmpty else { return nil }
            return ModemLightReading(label: String(label.prefix(Self.labelLimit)), color: light.color)
        }
        let kept = Array(lights.prefix(Self.lightLimit))
        verdicts = kept.enumerated().map { index, light in
            let othersLit = kept.indices.contains { $0 != index && kept[$0].color.isLit == true }
            return ModemLightVerdict(id: index, label: light.label, color: light.color, othersLit: othersLit)
        }
        isPanel = !verdicts.isEmpty
    }

    /// The app's meanings, worst first; lights it doesn't know aren't among them.
    public var keyPoints: [String] {
        verdicts.compactMap(\.meaning).enumerated()
            .sorted { ($0.element.severity, $1.offset) > ($1.element.severity, $0.offset) }
            .map(\.element.text)
    }

    /// The worst meaning, or nil when no light has one.
    public var worst: ModemLightSeverity? {
        verdicts.compactMap(\.meaning?.severity).max()
    }

    /// One line over the lights. Known lights without a verdict are counted, so an unclear
    /// light never hides behind an all-clear.
    public var headline: String {
        let severities = verdicts.compactMap(\.meaning?.severity)
        let problems = severities.count(where: { $0 == .problem })
        let attention = severities.count(where: { $0 == .attention })
        let unclear = verdicts.count(where: { $0.kind != nil && $0.meaning == nil })
        let summary = if problems > 0 {
            problems == 1 ? "1 light shows a problem." : "\(problems) lights show a problem."
        } else if attention > 0 {
            attention == 1 ? "1 light needs a look." : "\(attention) lights need a look."
        } else if severities.isEmpty {
            "The app doesn't know these lights."
        } else {
            "No light shows a problem."
        }
        guard unclear > 0 else { return summary }
        return summary + (unclear == 1 ? " 1 known light wasn't clear in the photo." : " \(unclear) known lights weren't clear in the photo.")
    }

    /// What the model is asked to word, or nil when there is nothing to word.
    public var insightRequest: InsightRequest? {
        guard isPanel else { return nil }
        return InsightRequest(
            subject: "Modem status lights read from a photo",
            // A light the app distrusts (`note`) is given as unclear, so the model can't state the reading.
            facts: verdicts.map { "Light labelled \($0.label): \($0.note == nil ? $0.color.word : ModemLightColor.unknown.word)" }
                + [Self.blinkingNote],
            observations: keyPoints
        )
    }
}
