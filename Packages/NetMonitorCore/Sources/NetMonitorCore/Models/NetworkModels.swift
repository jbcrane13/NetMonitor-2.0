import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

// MARK: - NetworkStatus

public struct NetworkStatus: Sendable {
    public let connectionType: ConnectionType
    public let isConnected: Bool
    public let isExpensive: Bool
    public let isConstrained: Bool
    public let wifi: WiFiInfo?
    public let gateway: GatewayInfo?
    public let publicIP: ISPInfo?
    public let updatedAt: Date

    public init(
        connectionType: ConnectionType = .none,
        isConnected: Bool = false,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        wifi: WiFiInfo? = nil,
        gateway: GatewayInfo? = nil,
        publicIP: ISPInfo? = nil
    ) {
        self.connectionType = connectionType
        self.isConnected = isConnected
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.wifi = wifi
        self.gateway = gateway
        self.publicIP = publicIP
        self.updatedAt = Date()
    }

    public static let disconnected = NetworkStatus()
}

// MARK: - WiFiInfo

public struct WiFiInfo: Sendable, Equatable {
    public let ssid: String
    public let bssid: String?
    public let signalStrength: Int?
    public let signalDBm: Int?
    public let channel: Int?
    public let frequency: String?
    public let band: WiFiBand?
    public let securityType: String?
    public let noiseLevel: Int?

    public init(
        ssid: String,
        bssid: String? = nil,
        signalStrength: Int? = nil,
        signalDBm: Int? = nil,
        channel: Int? = nil,
        frequency: String? = nil,
        band: WiFiBand? = nil,
        securityType: String? = nil,
        noiseLevel: Int? = nil
    ) {
        self.ssid = ssid
        self.bssid = bssid
        self.signalStrength = signalStrength
        self.signalDBm = signalDBm
        self.channel = channel
        self.frequency = frequency
        self.band = band
        self.securityType = securityType
        self.noiseLevel = noiseLevel
    }

    public var signalQuality: SignalQuality {
        guard let dbm = signalDBm else { return .unknown }
        switch dbm {
        case -50...0: return .excellent
        case -60 ..< -50: return .good
        case -70 ..< -60: return .fair
        default: return .poor
        }
    }

    public var signalBars: Int {
        guard let dbm = signalDBm else { return 0 }
        switch dbm {
        case -50...0: return 4
        case -60 ..< -50: return 3
        case -70 ..< -60: return 2
        case -80 ..< -70: return 1
        default: return 0
        }
    }
}

// MARK: - WiFiBand

public enum WiFiBand: String, Sendable {
    case band2_4GHz = "2.4 GHz"
    case band5GHz   = "5 GHz"
    case band6GHz   = "6 GHz"
}

// MARK: - SignalQuality

public enum SignalQuality: String, Sendable {
    case excellent = "Excellent"
    case good      = "Good"
    case fair      = "Fair"
    case poor      = "Poor"
    case unknown   = "Unknown"

#if canImport(SwiftUI)
    public var color: Color {
        switch self {
        case .excellent: .green
        case .good: .green
        case .fair: .orange
        case .poor: .red
        case .unknown: .secondary
        }
    }
#endif
}

// MARK: - GatewayInfo

public struct GatewayInfo: Sendable, Equatable {
    public let ipAddress: String
    public let macAddress: String?
    public let vendor: String?
    public let latency: Double?

    public init(
        ipAddress: String,
        macAddress: String? = nil,
        vendor: String? = nil,
        latency: Double? = nil
    ) {
        self.ipAddress = ipAddress
        self.macAddress = macAddress
        self.vendor = vendor
        self.latency = latency
    }

    public var latencyText: String? {
        guard let latency else { return nil }
        if latency < 1 { return "<1 ms" }
        return String(format: "%.0f ms", latency)
    }
}

// MARK: - ISPInfo

public struct ISPInfo: Sendable, Equatable {
    public let publicIP: String
    public let ispName: String?
    public let asn: String?
    public let organization: String?
    public let city: String?
    public let region: String?
    public let country: String?
    public let countryCode: String?
    public let timezone: String?
    public let fetchedAt: Date

    public init(
        publicIP: String,
        ispName: String? = nil,
        asn: String? = nil,
        organization: String? = nil,
        city: String? = nil,
        region: String? = nil,
        country: String? = nil,
        countryCode: String? = nil,
        timezone: String? = nil
    ) {
        self.publicIP = publicIP
        self.ispName = ispName
        self.asn = asn
        self.organization = organization
        self.city = city
        self.region = region
        self.country = country
        self.countryCode = countryCode
        self.timezone = timezone
        self.fetchedAt = Date()
    }

    public var locationText: String? {
        var parts: [String] = []
        if let city { parts.append(city) }
        if let c = countryCode ?? country { parts.append(c) }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
