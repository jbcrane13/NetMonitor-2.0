import Foundation

// MARK: - IPv4 Address Validation

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

// MARK: - CIDR Parsing

/// Errors that can occur when parsing CIDR notation.
public enum CIDRParseError: Error, Equatable {
    case invalidFormat
    case invalidIPAddress
    case invalidPrefixLength
}

/// Represents a parsed IPv4 CIDR block.
public struct IPv4CIDR: Sendable, Equatable {
    public let networkAddress: UInt32
    public let prefixLength: Int
    public let subnetMask: UInt32
    
    public init(networkAddress: UInt32, prefixLength: Int) {
        self.networkAddress = networkAddress
        self.prefixLength = prefixLength
        self.subnetMask = prefixLength > 0 ? (~UInt32(0)) << (32 - prefixLength) : 0
    }
    
    /// Parses a CIDR string in the format "xxx.xxx.xxx.xxx/xx".
    /// - Parameter cidr: The CIDR notation string
    /// - Throws: `CIDRParseError` if the format is invalid
    public init(parsing cidr: String) throws {
        let parts = cidr.split(separator: "/")
        guard parts.count == 2 else {
            throw CIDRParseError.invalidFormat
        }
        
        let ipPart = String(parts[0])
        guard isValidIPv4Address(ipPart) else {
            throw CIDRParseError.invalidIPAddress
        }
        
        guard let prefix = Int(parts[1]), prefix >= 0, prefix <= 32 else {
            throw CIDRParseError.invalidPrefixLength
        }
        
        self.prefixLength = prefix
        self.networkAddress = ipPart.ipv4ToUInt32() & ((~UInt32(0)) << (32 - prefix))
        self.subnetMask = prefix > 0 ? (~UInt32(0)) << (32 - prefix) : 0
    }
    
    /// The first usable host address (network address + 1).
    public var firstHost: UInt32 {
        networkAddress + 1
    }
    
    /// The last usable host address (broadcast - 1).
    public var lastHost: UInt32 {
        broadcastAddress - 1
    }
    
    /// The broadcast address for this subnet.
    public var broadcastAddress: UInt32 {
        networkAddress | ~subnetMask
    }
    
    /// Total number of usable host addresses.
    public var usableHostCount: Int {
        let count = Int(broadcastAddress - networkAddress - 1)
        return max(0, count)
    }
}

/// Extension to parse CIDR notation and generate host IP addresses.
public enum IPv4Helpers {
    /// Generates all usable host IP addresses from a CIDR notation string.
    ///
    /// - Parameter cidr: CIDR notation string (e.g., "192.168.1.0/24")
    /// - Returns: Array of IP address strings, or empty array if parsing fails
    public static func hostsInSubnet(cidr: String) -> [String] {
        guard let cidrBlock = try? IPv4CIDR(parsing: cidr) else {
            return []
        }
        
        // Limit to reasonable subnet sizes to prevent memory issues
        // Only allow /17 to /30 (max 32,766 hosts for /17, min 2 hosts for /30)
        // Skip /16 and larger (65k+ hosts), skip /31 and /32
        guard cidrBlock.prefixLength >= 17 && cidrBlock.prefixLength <= 30 else {
            return []
        }
        
        var hosts: [String] = []
        hosts.reserveCapacity(cidrBlock.usableHostCount)
        
        for host in cidrBlock.firstHost...cidrBlock.lastHost {
            hosts.append(host.ipv4ToString())
        }
        
        return hosts
    }
}

// MARK: - String Extensions for IPv4

private extension String {
    /// Converts a dotted-decimal IPv4 string to UInt32.
    func ipv4ToUInt32() -> UInt32 {
        let components = self.split(separator: ".")
        guard components.count == 4 else { return 0 }
        
        var result: UInt32 = 0
        for (index, component) in components.enumerated() {
            guard let octet = UInt8(component) else { return 0 }
            result |= UInt32(octet) << (24 - index * 8)
        }
        return result
    }
}

private extension UInt32 {
    /// Converts a UInt32 to dotted-decimal IPv4 string.
    func ipv4ToString() -> String {
        let octet1 = (self >> 24) & 0xFF
        let octet2 = (self >> 16) & 0xFF
        let octet3 = (self >> 8) & 0xFF
        let octet4 = self & 0xFF
        return "\(octet1).\(octet2).\(octet3).\(octet4)"
    }
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
