import Foundation

/// Maker and model read from a device's hostname, such as
/// `unifi-pro-max-16-switch.lan.example.net` → Ubiquiti, "UniFi Pro Max 16 Switch" (#439).
///
/// A hostname is only as accurate as whoever named the device, so this is the weakest
/// identity source. Callers use it only to fill a maker or model that every other source
/// (MAC prefix, Bonjour, UPnP, UniFi discovery, the Mac companion, earlier scans) left empty.
public struct HostnameIdentity: Equatable, Sendable {
    public let maker: String
    /// A model guess, or nil when the name carries only the brand (`hp-printer`).
    public let model: String?

    /// A brand word and the maker it stands for. `display` is set when the word is itself
    /// part of the product's name ("UniFi", "MacBook") and keeps that casing in the model.
    struct Brand {
        let maker: String
        let display: String?
        /// Matches the word followed by digits too: "usw24", "esp32".
        let matchesDigitSuffix: Bool
        /// Matches only with digits after it: "u7" is a UniFi access point, a bare "u" is nothing.
        let requiresDigitSuffix: Bool

        init(_ maker: String, display: String? = nil, digitSuffix: Bool = false, digitSuffixOnly: Bool = false) {
            self.maker = maker
            self.display = display
            self.matchesDigitSuffix = digitSuffix || digitSuffixOnly
            self.requiresDigitSuffix = digitSuffixOnly
        }
    }

    static let brands: [String: Brand] = [
        // Ubiquiti
        "unifi": Brand("Ubiquiti", display: "UniFi"),
        "ubnt": Brand("Ubiquiti"),
        "ubiquiti": Brand("Ubiquiti"),
        "usw": Brand("Ubiquiti", display: "USW", digitSuffix: true),
        "uap": Brand("Ubiquiti", display: "UAP", digitSuffix: true),
        "udm": Brand("Ubiquiti", display: "UDM", digitSuffix: true),
        "ucg": Brand("Ubiquiti", display: "UCG", digitSuffix: true),
        "uck": Brand("Ubiquiti", display: "UCK", digitSuffix: true),
        "u": Brand("Ubiquiti", display: "U", digitSuffixOnly: true),
        "cloudgateway": Brand("Ubiquiti", display: "UniFi Cloud Gateway"),
        "edgerouter": Brand("Ubiquiti", display: "EdgeRouter"),
        "edgeswitch": Brand("Ubiquiti", display: "EdgeSwitch"),
        // Other network gear
        "netgear": Brand("NETGEAR"),
        "orbi": Brand("NETGEAR", display: "Orbi"),
        "tplink": Brand("TP-Link"),
        "deco": Brand("TP-Link", display: "Deco"),
        "eero": Brand("eero", display: "eero"),
        "asus": Brand("ASUS"),
        "linksys": Brand("Linksys"),
        "velop": Brand("Linksys", display: "Velop"),
        "meraki": Brand("Cisco", display: "Meraki"),
        "cisco": Brand("Cisco"),
        "aruba": Brand("Aruba"),
        "mikrotik": Brand("MikroTik"),
        "gl": Brand("GL.iNet"),
        "synology": Brand("Synology"),
        "qnap": Brand("QNAP"),
        // Apple
        "macbook": Brand("Apple", display: "MacBook"),
        "mbp": Brand("Apple", display: "MacBook Pro"),
        "mba": Brand("Apple", display: "MacBook Air"),
        "imac": Brand("Apple", display: "iMac"),
        "macmini": Brand("Apple", display: "Mac mini"),
        "mac": Brand("Apple", display: "Mac"),
        "atv": Brand("Apple", display: "Apple TV"),
        "iphone": Brand("Apple", display: "iPhone"),
        "ipad": Brand("Apple", display: "iPad"),
        "appletv": Brand("Apple", display: "Apple TV"),
        "homepod": Brand("Apple", display: "HomePod"),
        // Home and media
        "sonos": Brand("Sonos"),
        "roku": Brand("Roku"),
        "chromecast": Brand("Google", display: "Chromecast"),
        "nest": Brand("Google", display: "Nest"),
        "google": Brand("Google"),
        "amazon": Brand("Amazon"),
        "kindle": Brand("Amazon", display: "Kindle"),
        "philips": Brand("Philips"),
        "hue": Brand("Philips", display: "Hue"),
        "ecobee": Brand("ecobee"),
        "meross": Brand("Meross"),
        "wiz": Brand("WiZ"),
        "aqara": Brand("Aqara"),
        "lutron": Brand("Lutron"),
        "dreame": Brand("Dreame"),
        "shelly": Brand("Shelly"),
        "tasmota": Brand("Tasmota"),
        "twinkly": Brand("Twinkly"),
        "wyze": Brand("Wyze"),
        "arlo": Brand("Arlo"),
        "samsung": Brand("Samsung"),
        "sony": Brand("Sony"),
        "vizio": Brand("VIZIO"),
        "shield": Brand("NVIDIA", display: "SHIELD"),
        "nvidia": Brand("NVIDIA"),
        "xbox": Brand("Microsoft", display: "Xbox"),
        "playstation": Brand("Sony", display: "PlayStation"),
        "nintendo": Brand("Nintendo"),
        "tesla": Brand("Tesla"),
        "raspberrypi": Brand("Raspberry Pi"),
        "esp": Brand("Espressif", display: "ESP", digitSuffix: true),
        // Printers
        "brother": Brand("Brother"),
        "epson": Brand("Epson"),
        "canon": Brand("Canon"),
        "hp": Brand("HP"),
        "lexmark": Brand("Lexmark"),
        "xerox": Brand("Xerox")
    ]

    /// Words shown in capitals inside a model.
    static let acronyms: Set<String> = ["poe", "nas", "lte", "sfp", "uhd"]

    /// Brand names written as two words in hostnames, joined before matching.
    static let joinedPairs: [(String, String)] = [
        ("tp", "link"), ("apple", "tv"), ("mac", "mini"), ("raspberry", "pi"), ("home", "pod"),
        ("cloud", "gateway")
    ]

    /// The identity from the first of `names` that has one: a device can carry a Bonjour
    /// name, a UPnP name and a DNS name, and any of them may be the one with the brand.
    public static func identify(names: [String?]) -> HostnameIdentity? {
        for name in names {
            if let name, !name.isEmpty, let identity = parse(hostname: name) {
                return identity
            }
        }
        return nil
    }

    /// Reads the first label of `hostname` (the part before the local domain). Nil when no
    /// brand word appears in it.
    public static func parse(hostname: String) -> HostnameIdentity? {
        let label = hostname.lowercased().split(separator: ".").first.map(String.init) ?? ""
        guard !label.isEmpty, label.rangeOfCharacter(from: .letters) != nil else { return nil }
        let words = joinPairs(label.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

        for (index, word) in words.enumerated() {
            guard let (brand, suffix) = match(word) else { continue }
            var rest = Array(words[(index + 1)...])
            // "unifi-controller" names software on some other computer, not a device.
            if let next = rest.first, softwareWords.contains(next) {
                return nil
            }
            // "iPhone-de-Juan": the owner's name follows a connector word.
            if let connector = rest.firstIndex(where: connectorWords.contains) {
                rest = Array(rest[..<connector])
            }
            // "Johns-MacBook-Pro-2": macOS and iOS add a single digit when two names clash.
            if let last = rest.last, last.count == 1, last.allSatisfy(\.isNumber) {
                rest.removeLast()
            }
            // "meross-mss620-ee73", "Aqara-Hub-M3-8548": many devices end their name with the
            // last four hex digits of their MAC.
            if rest.count > 1, let last = rest.last, last.count == 4, last.allSatisfy(\.isHexDigit),
               last.contains(where: \.isNumber) {
                rest.removeLast()
            }
            rest = rest.filter { !looksLikeSerial($0) }
            // "iPhone-91", "Blakes-iPad-12": Apple adds a number when names clash; no Apple
            // product name has a bare number in it.
            if brand.maker == "Apple" {
                rest = rest.filter { !$0.allSatisfy(\.isNumber) }
            }

            let model: String?
            if let display = brand.display {
                model = ([display + suffix] + rest.map(displayWord)).joined(separator: " ")
            } else if rest.contains(where: isModelCode) {
                // Without a product-line word, only a code like "l2350dw" or "m5" makes it a
                // model; "sonos-bedroom-2" names a room.
                model = rest.map(displayWord).joined(separator: " ")
            } else {
                model = nil
            }
            return HostnameIdentity(maker: brand.maker, model: model)
        }
        return nil
    }

    /// What a device's empty fields should get from this hostname, given what is already known.
    /// The maker only fills an empty one; the model only fills an empty one, and only when any
    /// known maker agrees with the hostname's ("Ubiquiti Inc" agrees with Ubiquiti).
    public func fills(knownMaker: String?, knownModel: String?) -> (maker: String?, model: String?) {
        let known = knownMaker.flatMap { $0.isEmpty ? nil : $0 }
        let firstWord = maker.lowercased().split(separator: " ").first.map(String.init) ?? maker.lowercased()
        let agrees = known.map { $0.lowercased().contains(firstWord) } ?? true
        let fillModel = (knownModel?.isEmpty ?? true) && agrees ? model : nil
        return (known == nil ? maker : nil, fillModel)
    }

    /// Words after a brand that mean the name is for software, not hardware.
    static let softwareWords: Set<String> = ["controller", "server", "app", "software"]
    /// Words that introduce an owner's name ("iPhone de Juan", "iPhone von Max").
    static let connectorWords: Set<String> = ["de", "da", "do", "di", "del", "von", "van", "du", "of", "la", "le"]

    /// Letters and digits together: "l2350dw", "m5", "u6".
    private static func isModelCode(_ word: String) -> Bool {
        word.contains(where: \.isNumber) && word.contains(where: \.isLetter)
    }

    private static func match(_ word: String) -> (Brand, String)? {
        if let brand = brands[word], !brand.requiresDigitSuffix {
            return (brand, "")
        }
        // "usw24" → USW + "24"; only for brands that allow it.
        guard let digitStart = word.firstIndex(where: \.isNumber) else { return nil }
        let prefix = String(word[..<digitStart])
        guard let brand = brands[prefix], brand.matchesDigitSuffix else { return nil }
        return (brand, String(word[digitStart...]).uppercased())
    }

    private static func joinPairs(_ words: [String]) -> [String] {
        var result: [String] = []
        var index = 0
        while index < words.count {
            if index + 1 < words.count, joinedPairs.contains(where: { $0 == (words[index], words[index + 1]) }) {
                result.append(words[index] + words[index + 1])
                index += 2
            } else {
                result.append(words[index])
                index += 1
            }
        }
        return result
    }

    /// A MAC or serial fragment: six or more hex characters ("a1b2c3"), or ten or more letters
    /// and digits ("f4dk75txxv", an Apple serial), with both a digit and a letter.
    static func looksLikeSerial(_ word: String) -> Bool {
        guard word.contains(where: \.isNumber), word.contains(where: \.isLetter) else { return false }
        return word.count >= 6 && word.allSatisfy(\.isHexDigit) || word.count >= 10
    }

    private static func displayWord(_ word: String) -> String {
        // "poe" → "POE" style acronyms, "l2350dw" → "L2350DW", "u6" → "U6", "hl" → "HL"
        if acronyms.contains(word) || word.contains(where: \.isNumber) && word.contains(where: \.isLetter)
            || word.count <= 2 && word.allSatisfy(\.isLetter) {
            return word == "poe" ? "PoE" : word.uppercased()
        }
        // "pro" → "Pro"; digits stay as they are
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
