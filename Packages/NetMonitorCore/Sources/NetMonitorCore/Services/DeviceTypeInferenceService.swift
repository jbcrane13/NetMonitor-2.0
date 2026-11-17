import Foundation

// MARK: - DeviceTypeInferenceService

/// A stateless service that infers `DeviceType` from network scan data
/// using a priority-based heuristic chain.
public struct DeviceTypeInferenceService: Sendable {

    public init() {}

    // MARK: - Rule Ports

    static let routerPorts: Set<Int> = [53, 80, 443]
    static let printerPorts: Set<Int> = [631, 9100]
    static let castPorts: Set<Int> = [8008, 8009]
    static let mediaServerPorts: Set<Int> = [32400]
    static let samsungTVPorts: Set<Int> = [8001, 8002]
    static let xboxPorts: Set<Int> = [3074]

    /// Every port a type rule looks at. A port scan must probe all of these, or the rule
    /// can never fire.
    public static let rulePorts: Set<Int> = routerPorts.union(printerPorts).union(castPorts)
        .union(mediaServerPorts).union(samsungTVPorts).union(xboxPorts)

    /// The quick fingerprinting port list scans use before type inference: common service
    /// ports plus every rule port.
    public static let fingerprintPorts: [Int] = [
        22, 53, 80, 443, 445, 548, 631, 3389, 5900, 8080, 8443, 8008, 9100, 32400, 62078,
        8001, 8002, 8009, 3074
    ]

    /// Infers the device type for a given `LocalDevice` based on network scan data.
    ///
    /// Only updates if the current `deviceType` is `.unknown` — never overrides
    /// user-set or previously inferred types.
    ///
    /// Priority chain (first match wins):
    /// 1. Gateway flag
    /// 2. Bonjour TXT model (#386)
    /// 3. Hostname patterns
    /// 4. Bonjour services
    /// 5. Open ports
    /// 6. Vendor / manufacturer
    /// 7. Falls back to current `device.deviceType`
    public func inferDeviceType(for device: LocalDevice) -> DeviceType {
        guard device.deviceType == .unknown else {
            return device.deviceType
        }

        // 1. Gateway check
        if device.isGateway {
            return .router
        }

        // 2. Exact model from Bonjour TXT records
        if let model = device.model, let result = Self.deviceType(forModel: model) {
            return result
        }

        // 3. Hostname-based inference
        if let result = inferFromHostnames(device) {
            return result
        }

        // 4. Bonjour services
        if let result = inferFromServices(device) {
            return result
        }

        // 5. Open ports
        if let result = inferFromPorts(device) {
            return result
        }

        // 6. Vendor / manufacturer
        if let result = inferFromVendor(device) {
            return result
        }

        // 7. No match — preserve current type
        return device.deviceType
    }

    // MARK: - Model Inference

    /// The type an exact model names: Apple model identifiers (`MacBookPro18,1`,
    /// `Mac16,10`, `iPhone15,2`, `AppleTV14,1`, `AudioAccessory5,1`) and Google Cast models
    /// (`Chromecast`, `Google Home Mini`). Board IDs (`J255AP`) and unknown makers' models
    /// return nil, so the other rules still run.
    public static func deviceType(forModel model: String) -> DeviceType? {
        let id = model.lowercased().trimmingCharacters(in: .whitespaces)
        if id.hasPrefix("macbook") {
            return .laptop
        }
        if id.hasPrefix("imac") || id.hasPrefix("macmini") || id.hasPrefix("macpro")
            || id.hasPrefix("macstudio") || isGenericMacIdentifier(id) {
            return .computer
        }
        if id.hasPrefix("iphone") {
            return .phone
        }
        if id.hasPrefix("ipad") {
            return .tablet
        }
        if id.hasPrefix("appletv") || id.contains("chromecast") || id.hasPrefix("google tv") {
            return .tv
        }
        if id.hasPrefix("audioaccessory") || id.hasPrefix("google home") || id.hasPrefix("google nest mini")
            || id.hasPrefix("nest audio") || id.hasPrefix("nest mini") {
            return .speaker
        }
        return nil
    }

    /// Newer Macs report "Mac" plus a number ("Mac16,10"), which doesn't say laptop or desktop.
    private static func isGenericMacIdentifier(_ id: String) -> Bool {
        guard id.hasPrefix("mac"), let next = id.dropFirst(3).first else { return false }
        return next.isNumber
    }

    // MARK: - Hostname Inference

    /// Distinctive product names still match inside glued names ("blakesiphone"). Short or
    /// common words (`nas`, `cam`, `canon`, `brother`) and multi-word names must match
    /// whole words (#389).
    private func inferFromHostnames(_ device: LocalDevice) -> DeviceType? {
        let names = [device.hostname, device.resolvedHostname, device.customName]
            .compactMap { $0.map(NameWords.init) }

        for name in names {
            if name.contains("iphone") {
                return .phone
            }
            if name.contains("ipad") {
                return .tablet
            }
            if name.contains("android") {
                return .phone
            }
            if name.contains("macbook") || name.contains("laptop") {
                return .laptop
            }
            if name.contains("imac") || name.has("mac pro")
                || name.has("mac mini") || name.has("mac studio") {
                return .computer
            }
            if name.contains("appletv") || name.has("apple tv") {
                return .tv
            }
            if name.contains("homepod") {
                return .speaker
            }
            if name.has("nas") || name.contains("synology")
                || name.contains("qnap") || name.contains("drobo") {
                return .storage
            }
            if name.contains("printer") || name.has("canon")
                || name.contains("epson") || name.has("brother") {
                return .printer
            }
            if name.contains("camera") || name.has("cam")
                || name.has("webcam") || name.has("ipcam") {
                return .camera
            }
            // "switch" alone is usually a network switch ("switch-24"), so a Nintendo
            // Switch is recognised by "nintendo".
            if name.contains("playstation") || name.contains("xbox")
                || name.contains("nintendo") {
                return .gaming
            }
        }

        return nil
    }

    // MARK: - Bonjour Service Inference

    private func inferFromServices(_ device: LocalDevice) -> DeviceType? {
        guard let services = device.discoveredServices else { return nil }

        let serviceSet = Set(services)

        if serviceSet.contains("_printer._tcp") || serviceSet.contains("_ipp._tcp")
            || serviceSet.contains("_pdl-datastream._tcp") {
            return .printer
        }
        if serviceSet.contains("_raop._tcp") {
            return .speaker
        }
        if serviceSet.contains("_airplay._tcp") {
            return .tv
        }
        if (serviceSet.contains("_smb._tcp") || serviceSet.contains("_afpovertcp._tcp"))
            && serviceSet.contains("_timemachine._tcp") {
            return .storage
        }

        return nil
    }

    // MARK: - Port-Based Inference

    private func inferFromPorts(_ device: LocalDevice) -> DeviceType? {
        guard let ports = device.openPorts else { return nil }
        return Self.inferFromPorts(Set(ports))
    }

    static func inferFromPorts(_ portSet: Set<Int>) -> DeviceType? {
        if portSet.isSuperset(of: routerPorts) {
            return .router
        }
        if !portSet.isDisjoint(with: printerPorts) {
            return .printer
        }
        if !portSet.isDisjoint(with: castPorts) {
            return .tv
        }
        if !portSet.isDisjoint(with: mediaServerPorts) {
            return .storage
        }

        return nil
    }

    // MARK: - Vendor / Manufacturer Inference

    /// Vendor names match whole words, so "RingCentral" is not Ring and "Intelligent" is
    /// not Intel (#389). Glued maker names that matched before ("ASUSTek", "LenovoEMC") are
    /// listed as their own words. "Hewlett Packard" (printer) and "Hewlett-Packard" (computer) keep
    /// their exact-text checks, since splitting into words would merge them.
    private func inferFromVendor(_ device: LocalDevice) -> DeviceType? {
        let vendors = [device.vendor, device.manufacturer]
            .compactMap { $0.map(NameWords.init) }

        guard !vendors.isEmpty else { return nil }

        for v in vendors {
            // Speakers
            if v.has("sonos") || v.has("bose") || v.has("harman") {
                return .speaker
            }
            // TVs
            if v.has("roku") || v.has("lg electronics") {
                return .tv
            }
            // Samsung — only TV if it has Tizen/smart-TV ports
            if v.has("samsung") {
                let ports = Set(device.openPorts ?? [])
                if !ports.isDisjoint(with: Self.samsungTVPorts) {
                    return .tv
                }
                // Otherwise fall through — don't return unknown yet
            }
            // Storage
            if v.has("synology") || v.has("qnap")
                || v.has("western digital") || v.has("drobo") {
                return .storage
            }
            // IoT
            if v.has("raspberry pi") || v.has("espressif") || v.has("tuya") {
                return .iot
            }
            // Cameras
            if v.has("ring") || v.has("nest") || v.has("wyze")
                || v.has("hikvision") || v.has("dahua") {
                return .camera
            }
            // Printers
            if v.has("canon") || v.has("epson") || v.has("brother")
                || v.has("hp inc") || v.contains("hewlett packard") {
                return .printer
            }
            // Gaming
            if v.has("nintendo") || v.has("sony interactive") {
                return .gaming
            }
            if v.has("microsoft") {
                let ports = Set(device.openPorts ?? [])
                if !ports.isDisjoint(with: Self.xboxPorts) {
                    return .gaming
                }
            }
            // Apple (generic fallback)
            if v.has("apple") {
                return .computer
            }
            // Computers
            if v.has("intel") || v.has("dell") || v.has("lenovo")
                || v.has("asus") || v.has("asustek") || v.has("lenovoemc")
                || v.contains("hewlett-packard") {
                return .computer
            }
        }

        return nil
    }
}

// MARK: - NameWords

/// A device or vendor name split into lowercased words on anything that is not a letter
/// or digit, and between letters and digits: "Switch-24" → ["switch", "24"],
/// "camera2" → ["camera", "2"], "Hewlett-Packard" → ["hewlett", "packard"].
struct NameWords {
    let text: String
    let words: [String]

    init(_ name: String) {
        text = name.lowercased()
        var words: [String] = []
        var current = ""
        var currentIsDigit = false
        for character in text {
            guard character.isLetter || character.isNumber else {
                if !current.isEmpty {
                    words.append(current)
                }
                current = ""
                continue
            }
            if !current.isEmpty, character.isNumber != currentIsDigit {
                words.append(current)
                current = ""
            }
            current.append(character)
            currentIsDigit = character.isNumber
        }
        if !current.isEmpty {
            words.append(current)
        }
        self.words = words
    }

    /// Whether the name has `phrase` as whole consecutive words ("mac mini").
    func has(_ phrase: String) -> Bool {
        let target = phrase.split(separator: " ").map(String.init)
        guard !target.isEmpty, target.count <= words.count else { return false }
        return (0...(words.count - target.count)).contains { start in
            Array(words[start..<(start + target.count)]) == target
        }
    }

    /// Whether `fragment` appears anywhere in the lowercased name.
    func contains(_ fragment: String) -> Bool {
        text.contains(fragment)
    }
}
