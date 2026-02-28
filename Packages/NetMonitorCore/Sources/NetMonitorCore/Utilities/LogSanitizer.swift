import Foundation

/// Utilities for sanitizing sensitive network data before logging.
///
/// Network diagnostics apps handle inherently sensitive data: IP addresses,
/// MAC addresses, hostnames, and SSIDs can identify users and their locations.
/// Use these helpers when logging values that could constitute PII.
///
/// ## Usage
/// ```swift
/// // Instead of:
/// Logger.network.debug("Connected to \(ipAddress)")
///
/// // Use:
/// Logger.network.debug("Connected to \(LogSanitizer.redactIP(ipAddress))")
/// // In release builds: "Connected to 192.168.x.x"
/// // In debug builds:   "Connected to 192.168.1.42"
/// ```
public enum LogSanitizer {

    // MARK: - IP Addresses

    /// Redacts the host portion of an IPv4 address in release builds.
    /// `192.168.1.42` → `192.168.x.x` (release) | `192.168.1.42` (debug)
    public static func redactIP(_ ip: String) -> String {
        #if DEBUG
        return ip
        #else
        let parts = ip.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return "x.x.x.x" }
        return "\(parts[0]).\(parts[1]).x.x"
        #endif
    }

    /// Redacts all but the first octet of an IPv4 address in release builds.
    /// Useful for subnet-level logging without exposing host identity.
    public static func redactIPFull(_ ip: String) -> String {
        #if DEBUG
        return ip
        #else
        return "x.x.x.x"
        #endif
    }

    // MARK: - MAC Addresses

    /// Redacts the device-specific portion of a MAC address in release builds.
    /// `AA:BB:CC:DD:EE:FF` → `AA:BB:CC:xx:xx:xx` (release)
    public static func redactMAC(_ mac: String) -> String {
        #if DEBUG
        return mac
        #else
        let parts = mac.uppercased().split(separator: ":")
        guard parts.count == 6 else { return "xx:xx:xx:xx:xx:xx" }
        return "\(parts[0]):\(parts[1]):\(parts[2]):xx:xx:xx"
        #endif
    }

    // MARK: - Hostnames and SSIDs

    /// Redacts a hostname to its TLD components in release builds.
    /// `mydevice.local` → `*.local` (release) | `mydevice.local` (debug)
    public static func redactHostname(_ hostname: String) -> String {
        #if DEBUG
        return hostname
        #else
        guard let dotIndex = hostname.lastIndex(of: ".") else { return "*.local" }
        let tld = hostname[dotIndex...]
        return "*\(tld)"
        #endif
    }

    /// Redacts an SSID to a fixed placeholder in release builds.
    public static func redactSSID(_ ssid: String) -> String {
        #if DEBUG
        return ssid
        #else
        return "<redacted-ssid>"
        #endif
    }

    // MARK: - Generic

    /// Redacts any string value in release builds, replacing it with a fixed marker.
    public static func redact(_ value: String, placeholder: String = "<redacted>") -> String {
        #if DEBUG
        return value
        #else
        return placeholder
        #endif
    }

    /// Returns a safe log representation of an optional string.
    /// Nil → "(nil)", non-nil → redacted or value depending on build.
    public static func redactOptional(_ value: String?, placeholder: String = "<redacted>") -> String {
        guard let value else { return "(nil)" }
        return redact(value, placeholder: placeholder)
    }
}
