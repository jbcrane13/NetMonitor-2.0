import Foundation

// MARK: - PingMethod

/// Whether a ping was performed via real ICMP or TCP handshake fallback.
public enum PingMethod: String, Sendable {
    case icmp = "ICMP"
    case tcp  = "TCP"
}

// MARK: - PingResult

/// Per-ping result from a single ICMP/TCP probe.
/// The canonical model — per-result streaming, not aggregate.
public struct PingResult: Identifiable, Sendable {
    public let id = UUID()
    public let sequence: Int
    public let host: String
    public let ipAddress: String?
    public let ttl: Int
    public let time: Double
    public let size: Int
    public let isTimeout: Bool
    public let timestamp: Date
    public let method: PingMethod

    public init(
        sequence: Int,
        host: String,
        ipAddress: String? = nil,
        ttl: Int,
        time: Double,
        size: Int = 64,
        isTimeout: Bool = false,
        method: PingMethod = .tcp
    ) {
        self.sequence = sequence
        self.host = host
        self.ipAddress = ipAddress
        self.ttl = ttl
        self.time = time
        self.size = size
        self.isTimeout = isTimeout
        self.timestamp = Date()
        self.method = method
    }

    public var timeText: String {
        if isTimeout {
            return "timeout"
        }
        if time < 1 {
            return String(format: "%.2f ms", time)
        }
        return String(format: "%.1f ms", time)
    }
}

// MARK: - PingStatistics

/// Aggregate summary computed from a collection of PingResults.
public struct PingStatistics: Sendable {
    public let host: String
    public let transmitted: Int
    public let received: Int
    public let packetLoss: Double
    public let minTime: Double
    public let maxTime: Double
    public let avgTime: Double
    public let stdDev: Double?

    public init(
        host: String,
        transmitted: Int,
        received: Int,
        packetLoss: Double,
        minTime: Double,
        maxTime: Double,
        avgTime: Double,
        stdDev: Double? = nil
    ) {
        self.host = host
        self.transmitted = transmitted
        self.received = received
        self.packetLoss = packetLoss
        self.minTime = minTime
        self.maxTime = maxTime
        self.avgTime = avgTime
        self.stdDev = stdDev
    }

    public var packetLossText: String {
        String(format: "%.1f%%", packetLoss)
    }

    public var successRate: Double {
        guard transmitted > 0 else { return 0 }
        return Double(received) / Double(transmitted) * 100
    }
}

// MARK: - TracerouteHop
// Uses `times` (not `latencies`) — canonical field name.

public struct TracerouteHop: Identifiable, Sendable {
    public let id = UUID()
    public let hopNumber: Int
    public let ipAddress: String?
    public let hostname: String?
    public let times: [Double]
    public let isTimeout: Bool
    public let timestamp: Date

    public init(
        hopNumber: Int,
        ipAddress: String? = nil,
        hostname: String? = nil,
        times: [Double] = [],
        isTimeout: Bool = false
    ) {
        self.hopNumber = hopNumber
        self.ipAddress = ipAddress
        self.hostname = hostname
        self.times = times
        self.isTimeout = isTimeout
        self.timestamp = Date()
    }

    public var displayAddress: String {
        if isTimeout {
            return "*"
        }
        return hostname ?? ipAddress ?? "*"
    }

    public var averageTime: Double? {
        guard !times.isEmpty else { return nil }
        return times.reduce(0, +) / Double(times.count)
    }

    public var timeText: String {
        if isTimeout {
            return "*"
        }
        guard let avg = averageTime else { return "*" }
        return String(format: "%.1f ms", avg)
    }
}

// MARK: - PortScanResult

public struct PortScanResult: Identifiable, Sendable {
    public let id = UUID()
    public let port: Int
    public let state: PortState
    public let serviceName: String?
    public let banner: String?
    public let responseTime: Double?

    public init(
        port: Int,
        state: PortState,
        serviceName: String? = nil,
        banner: String? = nil,
        responseTime: Double? = nil
    ) {
        self.port = port
        self.state = state
        self.serviceName = serviceName ?? Self.commonServiceName(for: port)
        self.banner = banner
        self.responseTime = responseTime
    }

    public static func commonServiceName(for port: Int) -> String? {
        let services: [Int: String] = [
            20: "FTP Data", 21: "FTP", 22: "SSH", 23: "Telnet",
            25: "SMTP", 53: "DNS", 67: "DHCP", 68: "DHCP",
            80: "HTTP", 110: "POP3", 119: "NNTP", 123: "NTP",
            143: "IMAP", 161: "SNMP", 194: "IRC", 443: "HTTPS",
            465: "SMTPS", 514: "Syslog", 587: "Submission",
            993: "IMAPS", 995: "POP3S", 1433: "MSSQL", 1521: "Oracle",
            3306: "MySQL", 3389: "RDP", 5432: "PostgreSQL",
            5900: "VNC", 6379: "Redis", 8080: "HTTP Alt",
            8443: "HTTPS Alt", 27017: "MongoDB"
        ]
        return services[port]
    }
}

// MARK: - PortState

public enum PortState: String, Sendable {
    case open
    case closed
    case filtered

    public var displayName: String { rawValue.capitalized }
}

// MARK: - DNSRecord

public struct DNSRecord: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let type: DNSRecordType
    public let value: String
    public let ttl: Int
    public let priority: Int?

    public init(
        name: String,
        type: DNSRecordType,
        value: String,
        ttl: Int,
        priority: Int? = nil
    ) {
        self.name = name
        self.type = type
        self.value = value
        self.ttl = ttl
        self.priority = priority
    }

    public var ttlText: String {
        if ttl >= 86400 {
            return "\(ttl / 86400)d"
        }
        if ttl >= 3600 {
            return "\(ttl / 3600)h"
        }
        if ttl >= 60 {
            return "\(ttl / 60)m"
        }
        return "\(ttl)s"
    }
}

// MARK: - DNSQueryResult

public struct DNSQueryResult: Sendable {
    public let domain: String
    public let server: String
    public let queryType: DNSRecordType
    public let records: [DNSRecord]
    public let queryTime: Double
    public let timestamp: Date

    public init(
        domain: String,
        server: String,
        queryType: DNSRecordType,
        records: [DNSRecord],
        queryTime: Double
    ) {
        self.domain = domain
        self.server = server
        self.queryType = queryType
        self.records = records
        self.queryTime = queryTime
        self.timestamp = Date()
    }

    public var queryTimeText: String {
        String(format: "%.0f ms", queryTime)
    }
}

// MARK: - BonjourService

public struct BonjourService: Identifiable, Sendable {
    public let id = UUID()
    public let name: String
    public let type: String
    public let domain: String
    public let hostName: String?
    public let port: Int?
    public let txtRecords: [String: String]
    public let addresses: [String]
    public let discoveredAt: Date

    public init(
        name: String,
        type: String,
        domain: String = "local.",
        hostName: String? = nil,
        port: Int? = nil,
        txtRecords: [String: String] = [:],
        addresses: [String] = []
    ) {
        self.name = name
        self.type = type
        self.domain = domain
        self.hostName = hostName
        self.port = port
        self.txtRecords = txtRecords
        self.addresses = addresses
        self.discoveredAt = Date()
    }

    public var fullType: String { "\(type).\(domain)" }

    public var serviceCategory: String {
        switch type {
        case "_http._tcp", "_https._tcp": "Web"
        case "_ssh._tcp", "_sftp._tcp": "Remote Access"
        case "_smb._tcp", "_afpovertcp._tcp": "File Sharing"
        case "_printer._tcp", "_ipp._tcp": "Printing"
        case "_airplay._tcp", "_raop._tcp": "AirPlay"
        case "_googlecast._tcp": "Chromecast"
        case "_spotify-connect._tcp": "Spotify"
        case "_homekit._tcp": "HomeKit"
        default: "Other"
        }
    }
}

// MARK: - SpeedTestServer

/// A known speed test server that can be selected by the user.
public struct SpeedTestServer: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let location: String
    /// URL used for download measurement (nil = auto/current behavior).
    public let downloadURL: String?
    /// URL used for upload measurement (nil = auto/current behavior).
    public let uploadURL: String?
    /// URL used for latency ping (nil = auto/current behavior).
    public let pingURL: String?
    /// When true this entry represents the automatic server selection fallback.
    public var isAutoSelect: Bool

    public init(
        id: String,
        name: String,
        location: String,
        downloadURL: String?,
        uploadURL: String?,
        pingURL: String? = nil,
        isAutoSelect: Bool = false
    ) {
        self.id = id
        self.name = name
        self.location = location
        self.downloadURL = downloadURL
        self.uploadURL = uploadURL
        self.pingURL = pingURL
        self.isAutoSelect = isAutoSelect
    }
}

// MARK: - SpeedTestServer Built-In List

public extension SpeedTestServer {
    /// The default "auto-select" entry that preserves the original Cloudflare behavior.
    static let autoSelect = SpeedTestServer(
        id: "auto",
        name: "Auto-select",
        location: "Nearest server",
        downloadURL: nil,
        uploadURL: nil,
        pingURL: nil,
        isAutoSelect: true
    )

    /// Cloudflare global CDN.
    static let cloudflare = SpeedTestServer(
        id: "cloudflare",
        name: "Cloudflare",
        location: "Global CDN",
        downloadURL: "https://speed.cloudflare.com/__down?bytes=10000000",
        uploadURL: "https://speed.cloudflare.com/__up",
        pingURL: "https://speed.cloudflare.com"
    )

    /// Linode/Akamai — Atlanta, GA (closest to SE US).
    static let linodeAtlanta = SpeedTestServer(
        id: "linode-atl",
        name: "Linode",
        location: "Atlanta, GA",
        downloadURL: "https://speedtest.atlanta.linode.com/100MB-atlanta.bin",
        uploadURL: nil,
        pingURL: "https://speedtest.atlanta.linode.com"
    )

    /// Linode/Akamai — Dallas, TX.
    static let linodeDallas = SpeedTestServer(
        id: "linode-dal",
        name: "Linode",
        location: "Dallas, TX",
        downloadURL: "https://speedtest.dallas.linode.com/100MB-dallas.bin",
        uploadURL: nil,
        pingURL: "https://speedtest.dallas.linode.com"
    )

    /// Vultr — Dallas, TX (supports both download and upload).
    static let vultrDallas = SpeedTestServer(
        id: "vultr-dal",
        name: "Vultr",
        location: "Dallas, TX",
        downloadURL: "https://tx-us-ping.vultr.com/vultr.com.100MB.bin",
        uploadURL: "https://tx-us-ping.vultr.com/vultr.com.100MB.bin",
        pingURL: "https://tx-us-ping.vultr.com"
    )

    /// Linode/Akamai — Newark, NJ.
    static let linodeNewark = SpeedTestServer(
        id: "linode-nwk",
        name: "Linode",
        location: "Newark, NJ",
        downloadURL: "https://speedtest.newark.linode.com/100MB-newark.bin",
        uploadURL: nil,
        pingURL: "https://speedtest.newark.linode.com"
    )

    /// OVH (France/Europe).
    static let ovh = SpeedTestServer(
        id: "ovh",
        name: "OVH",
        location: "France",
        downloadURL: "https://proof.ovh.net/files/100Mb.dat",
        uploadURL: nil,
        pingURL: "https://proof.ovh.net"
    )

    /// The canonical ordered list shown in the picker (auto-select first).
    static let all: [SpeedTestServer] = [
        .autoSelect,
        .cloudflare,
        .linodeAtlanta,
        .linodeDallas,
        .vultrDallas,
        .linodeNewark,
        .ovh
    ]
}

// MARK: - WHOISResult

public struct WHOISResult: Sendable {
    public let query: String
    public let registrar: String?
    public let creationDate: Date?
    public let expirationDate: Date?
    public let updatedDate: Date?
    public let nameServers: [String]
    public let status: [String]
    public let rawData: String
    public let queriedAt: Date

    // MARK: - Registrar detail (registrar-level referral / RDAP entity)

    public let registrarURL: String?
    public let registrarIANAID: String?
    public let abuseEmail: String?
    public let abusePhone: String?

    // MARK: - Registrant detail (when not redacted)

    public let registrantOrganization: String?
    public let registrantCountry: String?
    public let registrantState: String?

    /// "signed" / "unsigned", or nil if unknown.
    public let dnssec: String?

    // MARK: - IP WHOIS / RDAP "ip network" fields

    public let networkRange: String?
    public let networkName: String?
    public let networkOrganization: String?
    public let networkCountry: String?
    public let asn: String?

    public init(
        query: String,
        registrar: String? = nil,
        creationDate: Date? = nil,
        expirationDate: Date? = nil,
        updatedDate: Date? = nil,
        nameServers: [String] = [],
        status: [String] = [],
        rawData: String,
        registrarURL: String? = nil,
        registrarIANAID: String? = nil,
        abuseEmail: String? = nil,
        abusePhone: String? = nil,
        registrantOrganization: String? = nil,
        registrantCountry: String? = nil,
        registrantState: String? = nil,
        dnssec: String? = nil,
        networkRange: String? = nil,
        networkName: String? = nil,
        networkOrganization: String? = nil,
        networkCountry: String? = nil,
        asn: String? = nil
    ) {
        self.query = query
        self.registrar = registrar
        self.creationDate = creationDate
        self.expirationDate = expirationDate
        self.updatedDate = updatedDate
        self.nameServers = nameServers
        self.status = status
        self.rawData = rawData
        self.queriedAt = Date()
        self.registrarURL = registrarURL
        self.registrarIANAID = registrarIANAID
        self.abuseEmail = abuseEmail
        self.abusePhone = abusePhone
        self.registrantOrganization = registrantOrganization
        self.registrantCountry = registrantCountry
        self.registrantState = registrantState
        self.dnssec = dnssec
        self.networkRange = networkRange
        self.networkName = networkName
        self.networkOrganization = networkOrganization
        self.networkCountry = networkCountry
        self.asn = asn
    }

    public var domainAge: String? {
        guard let creation = creationDate else { return nil }
        let years = Calendar.current.dateComponents([.year], from: creation, to: Date()).year ?? 0
        return "\(years) years"
    }

    public var daysUntilExpiration: Int? {
        guard let expiration = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expiration).day
    }

    /// True once any IP-network field has been populated (i.e. this result came from an IP lookup).
    public var isIPNetworkResult: Bool {
        networkRange != nil || networkName != nil || networkOrganization != nil
    }
}

// MARK: - EPP domain status hints

/// Plain-language hints for common EPP domain status codes (RFC 8056 / icann.org/epp).
/// Matches both the RDAP wording ("client delete prohibited") and the WHOIS wording
/// ("clientDeleteProhibited https://icann.org/epp#clientDeleteProhibited") by
/// canonicalizing to a lowercase, letters-only token before lookup.
public enum EPPStatusHints {
    private static let hints: [String: String] = [
        "clientdeleteprohibited": "Registrar has blocked deletion of this domain.",
        "clienttransferprohibited": "Registrar has blocked transferring this domain to another registrar.",
        "clientupdateprohibited": "Registrar has blocked changes to this domain's records.",
        "clientrenewprohibited": "Registrar has blocked renewal of this domain.",
        "clienthold": "Registrar has taken this domain out of DNS (often a dispute or fraud hold).",
        "serverdeleteprohibited": "Registry has blocked deletion of this domain.",
        "servertransferprohibited": "Registry has blocked transferring this domain.",
        "serverupdateprohibited": "Registry has blocked changes to this domain's records.",
        "serverrenewprohibited": "Registry has blocked renewal of this domain.",
        "serverhold": "Registry has taken this domain out of DNS — usually a serious policy or legal issue.",
        "pendingdelete": "Domain is in the process of being deleted.",
        "pendingtransfer": "A transfer to another registrar is in progress.",
        "pendingupdate": "A change to this domain is in progress.",
        "pendingrenewal": "A renewal is in progress.",
        "pendingrestore": "Domain is being restored from a redemption grace period.",
        "pendingcreate": "Domain registration is in progress.",
        "redemptionperiod": "Domain was deleted and is in a grace period before its name is released.",
        "autorenewperiod": "Domain auto-renewed and is in a grace period where the renewal can still be reversed.",
        "addperiod": "Domain was just registered and is in an initial grace period.",
        "renewperiod": "Domain was just renewed and is in a grace period.",
        "transferperiod": "Domain was just transferred and is in a grace period.",
        "active": "Domain is active and resolving normally.",
        "ok": "Domain is active and resolving normally.",
        "inactive": "Domain has no nameservers delegated."
    ]

    /// Reduces a raw status string (from either RDAP or WHOIS text) to a lowercase,
    /// letters-only token suitable for hint lookup, e.g.
    /// "clientDeleteProhibited https://icann.org/epp#..." -> "clientdeleteprohibited"
    /// "client delete prohibited" -> "clientdeleteprohibited"
    public static func canonicalToken(for rawStatus: String) -> String {
        let codePhrase: String
        if let httpRange = rawStatus.range(of: "http") {
            codePhrase = String(rawStatus[rawStatus.startIndex..<httpRange.lowerBound])
        } else {
            codePhrase = rawStatus
        }
        return codePhrase.lowercased().filter { $0.isLetter }
    }

    /// A short plain-language explanation for a raw domain status string, if known.
    public static func hint(for rawStatus: String) -> String? {
        hints[canonicalToken(for: rawStatus)]
    }
}
