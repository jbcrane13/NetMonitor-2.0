import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - DeviceType

public enum DeviceType: String, Codable, CaseIterable, Sendable {
    case router
    case computer
    case laptop
    case phone
    case tablet
    case tv
    case speaker
    case gaming
    case iot
    case printer
    case camera
    case storage
    case unknown

    public var iconName: String {
        switch self {
        case .router: "wifi.router"
        case .computer: "desktopcomputer"
        case .laptop: "laptopcomputer"
        case .phone: "iphone"
        case .tablet: "ipad"
        case .tv: "appletv"
        case .speaker: "homepodmini"
        case .gaming: "gamecontroller"
        case .iot: "sensor"
        case .printer: "printer"
        case .camera: "web.camera"
        case .storage: "externaldrive"
        case .unknown: "questionmark.circle"
        }
    }

    public var displayName: String {
        switch self {
        case .router: "Router"
        case .computer: "Computer"
        case .laptop: "Laptop"
        case .phone: "Phone"
        case .tablet: "Tablet"
        case .tv: "TV"
        case .speaker: "Speaker"
        case .gaming: "Gaming"
        case .iot: "IoT Device"
        case .printer: "Printer"
        case .camera: "Camera"
        case .storage: "Storage"
        case .unknown: "Unknown"
        }
    }
}

// MARK: - StatusType

public enum StatusType: String, CaseIterable, Sendable {
    case online
    case offline
    case idle
    case unknown

    public var label: String {
        switch self {
        case .online: "Online"
        case .offline: "Offline"
        case .idle: "Idle"
        case .unknown: "Unknown"
        }
    }

    public var icon: String {
        switch self {
        case .online: "checkmark.circle.fill"
        case .offline: "xmark.circle.fill"
        case .idle: "moon.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }

#if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .online: .green
        case .offline: .red
        case .idle: .orange
        case .unknown: .gray
        }
    }
#endif
}

// MARK: - DeviceStatus

public enum DeviceStatus: String, Codable, CaseIterable, Sendable {
    case online
    case offline
    case idle

    public var statusType: StatusType {
        switch self {
        case .online: .online
        case .offline: .offline
        case .idle: .idle
        }
    }

#if canImport(SwiftUI)
    public var color: Color { statusType.color }
#endif
}

// MARK: - ConnectionType
// Raw values are intentionally lowercase for cross-platform persistence consistency.

public enum ConnectionType: String, Codable, CaseIterable, Sendable {
    case wifi     = "wifi"
    case cellular = "cellular"
    case ethernet = "ethernet"
    case none     = "none"

    public var iconName: String {
        switch self {
        case .wifi: "wifi"
        case .cellular: "antenna.radiowaves.left.and.right"
        case .ethernet: "cable.connector"
        case .none: "wifi.slash"
        }
    }

    public var displayName: String {
        switch self {
        case .wifi: "Wi-Fi"
        case .cellular: "Cellular"
        case .ethernet: "Ethernet"
        case .none: "No Connection"
        }
    }

    // MARK: Legacy migration support
    // Handles old macOS raw values ("WiFi", "Ethernet", "Cellular", "Unknown")
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        switch raw.lowercased() {
        case "wifi":     self = .wifi
        case "cellular": self = .cellular
        case "ethernet": self = .ethernet
        case "none", "unknown": self = .none
        default:         self = .none
        }
    }
}

// MARK: - ToolType

public enum ToolType: String, Codable, CaseIterable, Sendable {
    case ping
    case traceroute
    case dnsLookup
    case portScan
    case bonjourDiscovery
    case speedTest
    case whois
    case wakeOnLan
    case networkScan
    case subnetCalculator
    case worldPing
    case geoTrace
    case sslMonitor
    case wifiHeatmap
    case networkHealthScore
    case networkTimeline
    case scheduledScan
    case vpnInfo
    case exportPdf

    public var iconName: String {
        switch self {
        case .ping: "arrow.up.arrow.down"
        case .traceroute: "point.topleft.down.to.point.bottomright.curvepath"
        case .dnsLookup: "globe"
        case .portScan: "door.left.hand.open"
        case .bonjourDiscovery: "bonjour"
        case .speedTest: "speedometer"
        case .whois: "doc.text.magnifyingglass"
        case .wakeOnLan: "power"
        case .networkScan: "network"
        case .subnetCalculator: "square.split.bottomrightquarter"
        case .worldPing: "globe.americas"
        case .geoTrace: "map"
        case .sslMonitor: "lock.shield"
        case .wifiHeatmap: "wifi.circle"
        case .networkHealthScore: "heart.text.square"
        case .networkTimeline: "clock.arrow.circlepath"
        case .scheduledScan: "calendar.badge.clock"
        case .vpnInfo: "network.badge.shield.half.filled"
        case .exportPdf: "arrow.up.doc"
        }
    }

    public var displayName: String {
        switch self {
        case .ping: "Ping"
        case .traceroute: "Traceroute"
        case .dnsLookup: "DNS Lookup"
        case .portScan: "Port Scanner"
        case .bonjourDiscovery: "Bonjour Discovery"
        case .speedTest: "Speed Test"
        case .whois: "WHOIS"
        case .wakeOnLan: "Wake on LAN"
        case .networkScan: "Network Scan"
        case .subnetCalculator: "Subnet Calculator"
        case .worldPing: "World Ping"
        case .geoTrace: "Geo Trace"
        case .sslMonitor: "SSL Monitor"
        case .wifiHeatmap: "WiFi Heatmap"
        case .networkHealthScore: "Network Health Score"
        case .networkTimeline: "Network Timeline"
        case .scheduledScan: "Scheduled Scan"
        case .vpnInfo: "VPN Info"
        case .exportPdf: "Export PDF"
        }
    }

#if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .ping: .accentColor
        case .traceroute: .blue
        case .dnsLookup: .green
        case .portScan: .orange
        case .bonjourDiscovery: .accentColor
        case .speedTest: .green
        case .whois: .blue
        case .wakeOnLan: .red
        case .networkScan: .accentColor
        case .subnetCalculator: .purple
        case .worldPing: .teal
        case .geoTrace: .mint
        case .sslMonitor: .green
        case .wifiHeatmap: .blue
        case .networkHealthScore: .red
        case .networkTimeline: .indigo
        case .scheduledScan: .orange
        case .vpnInfo: .cyan
        case .exportPdf: .gray
        }
    }
#endif
}

// MARK: - TargetProtocol

public enum TargetProtocol: String, CaseIterable, Sendable {
    case icmp
    case tcp
    case http
    case https

    public var displayName: String {
        switch self {
        case .icmp: "ICMP (Ping)"
        case .tcp: "TCP"
        case .http: "HTTP"
        case .https: "HTTPS"
        }
    }

    public var defaultPort: Int? {
        switch self {
        case .icmp: nil
        case .tcp: 80
        case .http: 80
        case .https: 443
        }
    }
}

// Case-insensitive Codable conformance handles legacy uppercase values
// (e.g. "HTTPS" -> .https) stored by older versions of the app.
extension TargetProtocol: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        if let value = TargetProtocol(rawValue: raw.lowercased()) {
            self = value
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot initialize TargetProtocol from invalid String value \(raw)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue) // always writes lowercase
    }
}

// MARK: - DNSRecordType

public enum DNSRecordType: String, Codable, CaseIterable, Sendable {
    case a    = "A"
    case aaaa = "AAAA"
    case mx   = "MX"
    case txt  = "TXT"
    case cname = "CNAME"
    case ns   = "NS"
    case soa  = "SOA"
    case ptr  = "PTR"

    public var displayName: String { rawValue }
}

// MARK: - PortScanPreset

public enum PortScanPreset: String, CaseIterable, Sendable {
    case common
    case wellKnown
    case extended
    case web
    case database
    case mail
    case custom

    public var displayName: String {
        switch self {
        case .common: "Common Ports"
        case .wellKnown: "Well-Known (1-1024)"
        case .extended: "Extended (1-10000)"
        case .web: "Web Ports"
        case .database: "Database Ports"
        case .mail: "Mail Ports"
        case .custom: "Custom Range"
        }
    }

    public var ports: [Int] {
        switch self {
        case .common: PortScanPreset.commonPorts
        case .wellKnown: Array(1...1024)
        case .extended: Array(1...10000)
        case .web: PortScanPreset.webPorts
        case .database: PortScanPreset.databasePorts
        case .mail: PortScanPreset.mailPorts
        case .custom: []
        }
    }

    /// Whether this preset requires user-provided port range input
    public var isCustom: Bool { self == .custom }

    // MARK: Shared Port Lists

    public static let commonPorts: [Int] = [20, 21, 22, 23, 25, 53, 80, 110, 143, 443, 445, 993, 995, 3306, 3389, 5432, 5900, 8080, 8443]
    public static let webPorts: [Int] = [80, 443, 8080, 8443, 3000, 5000, 8000]
    public static let databasePorts: [Int] = [1433, 1521, 3306, 5432, 6379, 27017]
    public static let mailPorts: [Int] = [25, 110, 143, 465, 587, 993, 995]
}

// MARK: - PortRange

/// Represents a custom port range for scanning.
public struct PortRange: Sendable, Equatable {
    public var start: Int
    public var end: Int

    public init(start: Int = 1, end: Int = 1024) {
        self.start = max(1, min(start, 65535))
        self.end = max(1, min(end, 65535))
    }

    public var isValid: Bool {
        start >= 1 && end <= 65535 && start <= end
    }

    public var ports: [Int] {
        guard isValid else { return [] }
        return Array(start...end)
    }

    public var count: Int {
        guard isValid else { return 0 }
        return end - start + 1
    }
}
