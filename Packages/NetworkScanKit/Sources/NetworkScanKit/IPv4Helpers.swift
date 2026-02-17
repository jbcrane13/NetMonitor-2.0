import Foundation

/// Check whether a string is a valid dotted-decimal IPv4 address.
public func isValidIPv4Address(_ value: String) -> Bool {
    let components = value.split(separator: ".")
    guard components.count == 4 else { return false }

    for component in components {
        guard let octet = UInt8(component) else { return false }
        let componentText = String(component)
        if String(octet) != componentText && componentText != "0" {
            return false
        }
    }
    return true
}

/// Strip zone-ID suffix (e.g. `%en0`) and return the address only if it is valid IPv4.
public func cleanedIPv4Address(_ host: String) -> String? {
    let cleaned = host.split(separator: "%", maxSplits: 1).first.map(String.init) ?? host
    guard isValidIPv4Address(cleaned) else { return nil }
    return cleaned
}

/// Extract the first IPv4 address from an SSDP LOCATION header or response body.
public func extractIPFromSSDPResponse(_ response: String) -> String? {
    for line in response.split(whereSeparator: \.isNewline) {
        if line.lowercased().hasPrefix("location:"),
           let ip = firstIPv4Address(in: String(line)) {
            return ip
        }
    }
    return firstIPv4Address(in: response)
}

/// Find the first valid IPv4 address token inside arbitrary text.
public func firstIPv4Address(in text: String) -> String? {
    let tokens = text.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted)
    for token in tokens where isValidIPv4Address(token) {
        return token
    }
    return nil
}
