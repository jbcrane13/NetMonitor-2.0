import Foundation

// MARK: - What the model reads

/// A status light's colour, from a closed set (#558). The model names the colour; whether the
/// light is on is derived here: in the #447 spike it got every colour right but 4 of 8 on/off
/// answers wrong.
public enum ModemLightColor: String, Sendable, CaseIterable {
    case green, amber, red, blue, white
    /// Purple or magenta: lit, but no modem's table entry the app knows, so shown as read.
    case purple
    /// Dark or unlit.
    case off
    /// The model couldn't tell.
    case unknown

    /// True for a colour, false for off, nil when the colour isn't clear.
    public var isLit: Bool? {
        switch self {
        case .green, .amber, .red, .blue, .white, .purple: true
        case .off: false
        case .unknown: nil
        }
    }

    /// The words the model may answer with, `unknown` first. Purple isn't offered: with it in the
    /// list the real model read three unlit lights on a white case as unknown (#558 probe). A
    /// purple light then comes back as unknown, which is shown as read without a verdict.
    public static let modelValues = ["unknown", "off", "green", "amber", "orange", "yellow", "red", "blue", "white"]

    /// The colour for one of the model's words; anything outside the set is unknown.
    public init(modelValue: String) {
        switch modelValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "green": self = .green
        case "amber", "orange", "yellow": self = .amber
        case "red": self = .red
        case "blue": self = .blue
        case "white": self = .white
        case "purple", "magenta", "violet": self = .purple
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
    /// Derived from an off reading, which is only ever a check: the probe read lit white lights on a
    /// light case as off (lead decision on #558, option A).
    public var readsAsOff = false
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

    /// The app's name for the light, with its port or band: "Internet", "Ethernet 2". Nil for a
    /// label the app doesn't know. Built from the table, never from the model-read label's text.
    public var name: String? {
        ModemLightKind.match(label).map { $0.kind.name + ($0.qualifier.map { " " + $0 } ?? "") }
    }

    /// The light as read: "USB: green", "INTERNET: colour not clear", "LAN 2: reads as off". A
    /// power light the app distrusts (`note`) is "colour not clear".
    public var reading: String {
        let word = note != nil ? ModemLightColor.unknown.word : color == .off ? "reads as off" : color.word
        return "\(label): \(word)"
    }

    /// The table. One steady colour in one photo can't prove a link is up, so lit lines say what
    /// the light normally means and red is stated as read. Amber means different things across
    /// makers, so it is worded "on many modems" and kept from `problem`. Off is never a problem
    /// (#558 option A): it is a check worded as a question, since a lit white light on a light
    /// case reads as off. Purple has no entry.
    static func meaning(kind: ModemLightKind, qualifier: String?, color: ModemLightColor) -> ModemLightMeaning? {
        guard color != .unknown, color != .purple else { return nil }
        let name = kind.name + (qualifier.map { " " + $0 } ?? "")
        if color == .off {
            let (severity, clause) = offMeaning(kind: kind, isBand: qualifier != nil)
            return ModemLightMeaning(severity: severity, text: "\(name) reads as off. If it is dark, \(clause)", readsAsOff: true)
        }
        let (lit, amber, red) = clauses(kind: kind, isBand: qualifier != nil)
        switch color {
        case .amber:
            return ModemLightMeaning(severity: .attention, text: "\(name) light is amber: \(amber)")
        case .red:
            // Phone service is the one red that isn't the connection itself.
            return ModemLightMeaning(severity: kind == .phone ? .attention : .problem, text: "\(name) light reads as red: this normally means \(red)")
        default:
            return ModemLightMeaning(severity: .normal, text: "\(name) light is \(color.rawValue): this normally means \(lit)")
        }
    }

    /// What each light normally means when lit, amber and red.
    private static func clauses(kind: ModemLightKind, isBand: Bool) -> (lit: String, amber: String, red: String) {
        switch kind {
        case .power:
            ("the modem has power.", "on many modems this means it is starting up or has a fault.", "a hardware fault or a failed start-up.")
        case .broadband:
            ("the line from your provider is connected.", "on many modems this means the line is still connecting or is weak.",
             "the modem has no line from your provider.")
        case .internet:
            ("the modem is online.", "on many modems this means it reaches your provider but isn't online.", "the modem has no internet connection.")
        case .wifi:
            (isBand ? "that Wi-Fi band is on." : "Wi-Fi is on.", "on many modems this means Wi-Fi is pairing a device (WPS) or has a fault.",
             "Wi-Fi has a fault.")
        case .ethernet:
            ("a device is connected to that port.", "on many modems this means a device is connected at a slower speed.", "a fault on that port.")
        case .phone:
            ("phone service is ready.", "on many modems this means phone service has a problem.", "phone service has a problem.")
        case .wan:
            ("the router has a link to the modem or provider. That alone doesn't show the internet is working.",
             "on many routers this means the WAN link is up but the internet isn't.", "there is no internet connection on the WAN port.")
        case .upstream, .downstream:
            kind == .upstream
                ? ("the modem is connected to your provider's upstream channels.",
                   "on many modems this means it is still connecting, or connected on fewer channels.",
                   "the modem has no upstream connection to your provider.")
                : ("the modem is connected to your provider's downstream channels.",
                   "on many modems this means it is still connecting, or connected on fewer channels.",
                   "the modem has no downstream connection to your provider.")
        }
    }

    /// What a dark light would mean: a check for the lights that matter, a note where off is often expected.
    private static func offMeaning(kind: ModemLightKind, isBand: Bool) -> (ModemLightSeverity, String) {
        switch kind {
        case .power: (.attention, "the modem has no power: check its power cable and outlet.")
        case .broadband: (.attention, "the modem has no line from your provider: check the cable to the wall socket.")
        case .internet: (.attention, "the modem isn't online.")
        case .wifi where isBand: (.note, "that Wi-Fi band is turned off on this unit.")
        case .wifi: (.note, "Wi-Fi is turned off on this unit. That is expected if you use a separate router.")
        case .ethernet: (.note, "nothing is connected to that port, or the connected device is off.")
        case .phone: (.note, "phone service is off or not set up. That is expected if you don't use it.")
        case .wan: (.attention, "nothing is connected to the WAN port, or the modem it connects to is off.")
        case .upstream: (.attention, "the modem has no upstream connection to your provider.")
        case .downstream: (.attention, "the modem has no downstream connection to your provider.")
        }
    }
}

// MARK: - Report

/// The app's reading of a photo of a modem's lights (#558): each light as read and the app's
/// meanings. Every line shown is the app's own text; the model only reads labels and colours. Pure.
public struct ModemPanelReport: Sendable, Equatable {
    /// Most lights kept, and the longest label.
    public static let lightLimit = 16
    public static let labelLimit = 24
    /// Shown under every reading.
    public static let blinkingNote = "Whether a light is blinking can't be seen in one photo"
    /// Shown under every reading: the real-model probe read lit white lights on a light case as off.
    public static let whiteLightNote = "White lights on a light-coloured case may read as off."

    /// False when the model said the photo isn't a panel of status lights, or read none.
    public let isPanel: Bool
    public let verdicts: [ModemLightVerdict]
    /// The model listed more lights than the app keeps.
    public let isPartial: Bool

    public init(answer: ModemPanelAnswer) {
        guard answer.status == .panel else {
            isPanel = false
            verdicts = []
            isPartial = false
            return
        }
        let lights = answer.lights.compactMap { light -> ModemLightReading? in
            let label = InsightRequest.line(light.label, limit: .max)
                .components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
            guard !label.isEmpty else { return nil }
            return ModemLightReading(label: String(label.prefix(Self.labelLimit)), color: light.color)
        }
        let kept = Array(lights.prefix(Self.lightLimit))
        isPartial = lights.count > Self.lightLimit
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

    /// Lines shown above the lights when the reading itself is in doubt.
    public var notices: [String] {
        var notices: [String] = []
        if isPartial {
            notices.append("The photo shows more lights than the app reads at once. Only the first \(Self.lightLimit) are listed.")
        }
        if verdicts.count(where: { $0.kind == .power }) > 1 {
            notices.append("This photo may show more than one device.")
        }
        return notices
    }

    /// Lights the app doesn't know, lit red or amber: never behind an all-clear.
    public var unknownColoured: [ModemLightVerdict] {
        verdicts.filter { $0.kind == nil && ($0.color == .red || $0.color == .amber) }
    }

    /// Whether the headline is the all-clear, "No light shows a problem": some light has a meaning,
    /// and none is red, amber, read as off, or an unknown light lit red or amber. The troubleshooter
    /// uses the same rule (#625), so the sheet and the findings can't disagree.
    public var isAllClear: Bool {
        let meanings = verdicts.compactMap(\.meaning)
        return !meanings.isEmpty && unknownColoured.isEmpty && meanings.allSatisfy { $0.severity == .normal }
    }

    /// The all-clear, with every known light read clearly and every light kept: the troubleshooter's
    /// weak "the lights look normal" fact (#625). Never proof the connection works.
    public var looksNormal: Bool {
        isAllClear && notices.isEmpty && !verdicts.contains { $0.kind != nil && $0.meaning == nil }
    }

    /// One line over the lights, worst first. It says "No light shows a problem" only when no
    /// light is red, amber, read as off, or an unknown light lit red or amber (`isAllClear`); known
    /// lights without a verdict are counted too, so nothing hides behind an all-clear.
    public var headline: String {
        let meanings = verdicts.compactMap(\.meaning)
        let problems = meanings.count(where: { $0.severity == .problem })
        let off = meanings.count(where: \.readsAsOff)
        let attention = meanings.count(where: { $0.severity == .attention && !$0.readsAsOff })
        let unknownColoured = unknownColoured
        let unclear = verdicts.count(where: { $0.kind != nil && $0.meaning == nil })
        var parts: [String] = []
        if problems > 0 {
            parts.append(problems == 1 ? "1 light shows a problem." : "\(problems) lights show a problem.")
        }
        if let first = unknownColoured.first {
            let labels = unknownColoured.map(\.label).joined(separator: ", ")
            parts.append(unknownColoured.count == 1
                ? "1 light is \(first.color.rawValue): \(labels). The app doesn't know this light; check your modem's guide."
                : "\(unknownColoured.count) lights are red or amber: \(labels). The app doesn't know these lights; check your modem's guide.")
        }
        if off > 0 {
            parts.append(off == 1 ? "1 light reads as off: check it." : "\(off) lights read as off: check them.")
        }
        if attention > 0 {
            parts.append(attention == 1 ? "1 light needs a look." : "\(attention) lights need a look.")
        }
        if isAllClear {
            parts.append("No light shows a problem.")
        } else if parts.isEmpty {
            parts.append("The app doesn't know these lights.")
        }
        if unclear > 0 {
            parts.append(unclear == 1 ? "1 known light wasn't clear in the photo." : "\(unclear) known lights weren't clear in the photo.")
        }
        return parts.joined(separator: " ")
    }
}
