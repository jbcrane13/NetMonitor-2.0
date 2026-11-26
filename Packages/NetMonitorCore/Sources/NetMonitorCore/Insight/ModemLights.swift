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

    /// The light as read: "USB: green", "INTERNET: colour not clear", "LAN 2: reads as off".
    public var reading: String {
        "\(label): \(color == .off ? "reads as off" : color.word)"
    }

    /// The table. Amber, blue and white mean different things across makers, so those are
    /// worded "on many modems" and kept from `problem`. Off is never a problem (#558 option A):
    /// it is a check worded as a question, since a lit white light on a light case reads as off.
    static func meaning(kind: ModemLightKind, qualifier: String?, color: ModemLightColor) -> ModemLightMeaning? {
        guard color != .unknown else { return nil }
        let name = kind.name + (qualifier.map { " " + $0 } ?? "")
        if color == .off {
            let (severity, clause) = offMeaning(kind: kind, isBand: qualifier != nil)
            return ModemLightMeaning(severity: severity, text: "\(name) reads as off. If it is dark, \(clause)", readsAsOff: true)
        }
        let lit = color == .green || color == .blue || color == .white
        let amber = color == .amber
        let entry: (ModemLightSeverity, String)
        switch kind {
        case .power:
            entry = lit ? (.normal, "the modem has power.")
                : amber ? (.attention, "on many modems this means it is starting up or has a fault.")
                : (.problem, "on most modems this means a hardware fault or a failed start-up.")
        case .broadband:
            entry = lit ? (.normal, "the line from your provider is connected.")
                : amber ? (.attention, "on many modems this means the line is still connecting or is weak.")
                : (.problem, "the modem has no line from your provider.")
        case .internet:
            entry = lit ? (.normal, "the modem is connected to the internet.")
                : amber ? (.attention, "on many modems this means it reaches your provider but isn't online.")
                : (.problem, "the modem has no internet connection.")
        case .wifi:
            entry = lit ? (.normal, qualifier == nil ? "Wi-Fi is on." : "that Wi-Fi band is on.")
                : amber ? (.attention, "on many modems this means Wi-Fi is pairing a device (WPS) or has a fault.")
                : (.problem, "on most modems this means Wi-Fi has a fault.")
        case .ethernet:
            entry = lit ? (.normal, "a device is connected to that port.")
                : amber ? (.attention, "on many modems this means a device is connected at a slower speed.")
                : (.problem, "on many modems this means a fault on that port.")
        case .phone:
            entry = lit ? (.normal, "phone service is ready.") : (.attention, "on many modems this means phone service has a problem.")
        case .wan:
            entry = lit ? (.normal, "the router has a link to the modem or provider. That alone doesn't show the internet is working.")
                : amber ? (.attention, "on many routers this means the WAN link is up but the internet isn't.")
                : (.problem, "on most routers this means there is no internet connection on the WAN port.")
        case .upstream, .downstream:
            let direction = kind == .upstream ? "upstream" : "downstream"
            entry = lit ? (.normal, "the modem is connected to your provider's \(direction) channels.")
                : amber ? (.attention, "on many modems this means it is still connecting, or connected on fewer channels.")
                : (.problem, "the modem has no \(direction) connection to your provider.")
        }
        return ModemLightMeaning(severity: entry.0, text: "\(name) light is \(color.rawValue): \(entry.1)")
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

/// The app's reading of a photo of a modem's lights (#558): each light as read, the app's
/// meanings, and the request the model words them from. Pure.
public struct ModemPanelReport: Sendable, Equatable {
    /// Most lights kept, and the longest label.
    public static let lightLimit = 16
    public static let labelLimit = 24
    /// Shown under every reading, and given to the model as a fact.
    public static let blinkingNote = "Whether a light is blinking can't be seen in one photo"
    /// Shown under every reading: the real-model probe read lit white lights on a light case as off.
    public static let whiteLightNote = "White lights on a light-coloured case may read as off."

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

    /// One line over the lights. Off lights that matter are counted as lights to check, never as
    /// problems; known lights without a verdict are counted, so neither hides behind an all-clear.
    public var headline: String {
        let meanings = verdicts.compactMap(\.meaning)
        let problems = meanings.count(where: { $0.severity == .problem })
        let attention = meanings.count(where: { $0.severity == .attention && !$0.readsAsOff })
        let checks = meanings.count(where: { $0.severity == .attention && $0.readsAsOff })
        let unclear = verdicts.count(where: { $0.kind != nil && $0.meaning == nil })
        var line = if problems > 0 {
            problems == 1 ? "1 light shows a problem." : "\(problems) lights show a problem."
        } else if attention > 0 {
            attention == 1 ? "1 light needs a look." : "\(attention) lights need a look."
        } else if meanings.isEmpty {
            "The app doesn't know these lights."
        } else {
            "No light shows a problem."
        }
        if checks > 0 {
            line += checks == 1 ? " 1 light reads as off: check it." : " \(checks) lights read as off: check them."
        }
        if unclear > 0 {
            line += unclear == 1 ? " 1 known light wasn't clear in the photo." : " \(unclear) known lights weren't clear in the photo."
        }
        return line
    }

    private static func factColor(_ verdict: ModemLightVerdict) -> String {
        if verdict.note != nil {
            return ModemLightColor.unknown.word
        }
        return verdict.color == .off ? "reads as off (check)" : verdict.color.word
    }

    /// Whether a light that matters reads as off, which the user has to check.
    public var hasChecks: Bool {
        verdicts.contains { $0.meaning?.readsAsOff == true && $0.meaning?.severity == .attention }
    }

    /// What the model is asked to word, or nil when there is nothing to word. Nil too while a light
    /// needs a check: in the real-model probe, "reads as off (check)" came back as "the modem is not
    /// online" and "no power is supplied", so only the app's own lines are shown then.
    public var insightRequest: InsightRequest? {
        guard isPanel, !hasChecks else { return nil }
        return InsightRequest(
            subject: "Modem status lights read from a photo",
            // A light the app distrusts (`note`) is given as unclear, and an off reading as one to
            // check, so the wording can't state the one or assert a fault from the other.
            facts: verdicts.map { "Light labelled \($0.label): \(Self.factColor($0))" } + [Self.blinkingNote],
            observations: keyPoints
        )
    }
}
