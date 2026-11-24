import Foundation

/// How much a finding matters, highest first when ranked (#454).
public enum SecuritySeverity: Int, Comparable, Sendable, CaseIterable {
    case low
    case medium
    case high

    public static func < (lhs: SecuritySeverity, rhs: SecuritySeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The word the readout and the model's facts use, such as "high".
    public var label: String {
        switch self {
        case .low: "low"
        case .medium: "medium"
        case .high: "high"
        }
    }
}

/// One rule of the security readout: an open TCP port, optionally only on some device types,
/// with the severity, title, explanation and remedy the app shows for it (#454). The text is
/// fixed, so the readout is complete without the on-device model.
public struct SecurityRule: Sendable {
    /// Stable id, such as "telnet".
    public let id: String
    /// The TCP ports this rule reads.
    public let ports: Set<Int>
    /// The service the port carries, as the title names it, such as "Telnet".
    public let service: String
    /// The device types the rule applies to; nil for every type.
    public let deviceTypes: Set<DeviceType>?
    /// Severity on a device type with no override, including `.unknown`.
    public let severity: SecuritySeverity
    /// Severity on these device types instead of `severity`.
    public let severityByType: [DeviceType: SecuritySeverity]
    public let explanation: String
    public let remedy: String
    /// A title for every port instead of "<service> port <n> is open", for a rule whose service is
    /// only likely, such as UPnP on port 5000.
    let fixedTitle: String?

    /// Internal: the rules are `SecurityRuleTable.rules` alone, so every finding traces to a rule
    /// reviewed there; callers outside Core read rules and can't add one.
    init(
        id: String,
        ports: Set<Int>,
        service: String,
        deviceTypes: Set<DeviceType>? = nil,
        severity: SecuritySeverity,
        severityByType: [DeviceType: SecuritySeverity] = [:],
        title: String? = nil,
        explanation: String,
        remedy: String
    ) {
        fixedTitle = title
        self.id = id
        self.ports = ports
        self.service = service
        self.deviceTypes = deviceTypes
        self.severity = severity
        self.severityByType = severityByType
        self.explanation = explanation
        self.remedy = remedy
    }

    /// Whether the rule reads `port` on a device of `type`.
    public func applies(port: Int, deviceType type: DeviceType) -> Bool {
        ports.contains(port) && (deviceTypes?.contains(type) ?? true)
    }

    /// The severity on a device of `type`.
    public func severity(for type: DeviceType) -> SecuritySeverity {
        severityByType[type] ?? severity
    }

    /// States what was measured, never more: "Telnet port 23 is open".
    public func title(port: Int) -> String {
        fixedTitle ?? "\(service) port \(port) is open"
    }
}

/// One risk the readout lists: one rule plus one open port measured on one device (#454).
/// Computed from the current device rows, never stored, so it follows its device through a
/// rename or a record merge.
///
/// Its memberwise init stays internal: only `SecurityRuleTable.findings(for:)` makes findings, from
/// a rule and a port in `openPorts`, so nothing outside Core can list an unmeasured one.
public struct SecurityFinding: Sendable, Equatable, Identifiable {
    /// Unique per device, rule and port.
    public let id: String
    /// `LocalDevice.id`, for opening the device.
    public let deviceID: UUID
    /// `LocalDevice.displayName` when the finding was computed.
    public let deviceName: String
    public let port: Int
    public let ruleID: String
    public let service: String
    public let severity: SecuritySeverity
    public let title: String
    public let explanation: String
    public let remedy: String
}

/// The deterministic rules behind the security readout (#454). The app decides every finding
/// and its severity here; the on-device model only words an overview of them.
///
/// Findings come only from `LocalDevice.openPorts`, which holds ports a TCP probe found open
/// (the Mac's quick scan, `QuickPortScanPhase`, probes every port in `ports`). UDP services such
/// as SNMP (161) and SSDP/UPnP (1900) are left out: a TCP connect can't measure them.
public enum SecurityRuleTable {
    /// The rules in tie-break order: of two findings with the same severity, the earlier rule ranks first.
    public static let rules: [SecurityRule] = [
        // Telnet sends the login and everything after it unencrypted, and it is how botnets
        // such as Mirai take over cameras and routers with default passwords. High everywhere.
        SecurityRule(
            id: "telnet", ports: [23], service: "Telnet", severity: .high,
            explanation: "Telnet sends the password and the whole session unencrypted, and attackers scan for it to log in with default passwords.",
            remedy: "Turn Telnet off in the device's settings and use SSH or the maker's app instead. "
                + "If it can't be turned off, keep the device off untrusted networks."
        ),
        // FTP logins and files travel unencrypted. On a NAS that exposes the stored files, and
        // cameras and smart devices often ship it with a default login.
        SecurityRule(
            id: "ftp", ports: [21], service: "FTP", severity: .medium,
            severityByType: [.storage: .high, .camera: .high, .iot: .high],
            explanation: "FTP sends the login and the files unencrypted, so anyone on the network can read them.",
            remedy: "Turn FTP off, or switch to SFTP or FTPS if the device offers it."
        ),
        // RDP is a remote-control door; it should only be open on computers meant to be controlled.
        SecurityRule(
            id: "rdp", ports: [3389], service: "Remote Desktop (RDP)", severity: .medium,
            explanation: "Remote Desktop lets someone control this device over the network, and it is a common target for password guessing.",
            remedy: "Turn Remote Desktop off if you don't use it. If you do, use a strong password and network-level authentication."
        ),
        // VNC passwords are often short or absent. Screen Sharing on a Mac uses this port and is
        // a deliberate choice (medium); on a camera or smart device it is unexpected (high).
        SecurityRule(
            id: "vnc", ports: [5900], service: "VNC screen sharing", severity: .medium,
            severityByType: [.camera: .high, .iot: .high],
            explanation: "VNC lets someone see and control the screen over the network, and its passwords are often weak or missing.",
            remedy: "Turn screen sharing off if you don't use it, or require a strong password."
        ),
        // Redis has no password by default and its commands can write files on the host.
        SecurityRule(
            id: "redis", ports: [6379], service: "Redis database", severity: .high,
            explanation: "Redis answers anyone who connects unless a password is set, and its commands can change files on the device.",
            remedy: "Bind Redis to the device itself or set a password, and only open it to the apps that need it."
        ),
        // Older MongoDB releases accept connections without a login.
        SecurityRule(
            id: "mongodb", ports: [27017], service: "MongoDB database", severity: .high,
            explanation: "A reachable MongoDB database may let anyone on the network read or delete its data if access control is off.",
            remedy: "Turn on MongoDB access control and bind it to the device itself unless other devices need it."
        ),
        // Databases protected by a login, but still a target for password guessing on the LAN.
        SecurityRule(
            id: "mysql", ports: [3306], service: "MySQL database", severity: .medium,
            explanation: databaseExplanation,
            remedy: databaseRemedy
        ),
        SecurityRule(
            id: "postgresql", ports: [5432], service: "PostgreSQL database", severity: .medium,
            explanation: databaseExplanation,
            remedy: databaseRemedy
        ),
        // SMB file sharing is expected on a NAS or a computer (low: keep it patched, no guest
        // access); elsewhere it is unusual. Old SMB versions carried worms such as WannaCry.
        SecurityRule(
            id: "smb", ports: [445], service: "SMB file sharing", severity: .medium,
            severityByType: [.storage: .low, .computer: .low, .laptop: .low],
            explanation: "File sharing lets other devices on the network open shared folders; old versions and guest access have let malware spread.",
            remedy: "Keep the device's software up to date, turn off guest access and SMB version one, and share only the folders you need."
        ),
        // Admin pages over plain HTTP send the admin password unencrypted. Only routers, cameras
        // and printers: on other devices port 80 is usually an ordinary web page.
        SecurityRule(
            id: "http-admin", ports: [80, 8080], service: "HTTP admin page",
            deviceTypes: [.router, .camera, .printer], severity: .medium,
            severityByType: [.printer: .low],
            explanation: "This device answers on unencrypted HTTP. If its settings page is served there rather than redirected to HTTPS, "
                + "the admin password can be read by others on the network.",
            remedy: "Use the HTTPS address if the device has one, change the default admin password, and turn off the HTTP page if you can."
        ),
        // Legacy NetBIOS session service, from the era of SMB version one.
        SecurityRule(
            id: "netbios", ports: [139], service: "NetBIOS file sharing", severity: .low,
            explanation: "NetBIOS is an old way of sharing files and names that newer devices no longer need.",
            remedy: "Turn NetBIOS off in the device's sharing settings if nothing on the network needs it."
        ),
        // Many router firmwares serve UPnP control on TCP 5000; UPnP lets any device on the LAN
        // open ports to the internet. Routers only: macOS AirPlay Receiver listens on 5000 too.
        SecurityRule(
            id: "upnp", ports: [5000], service: "Possible UPnP", deviceTypes: [.router], severity: .low,
            title: "Port 5000 (often UPnP) is open",
            explanation: "Routers often use this port for UPnP, which lets any device on the network open ports to the internet without asking.",
            remedy: "Turn UPnP off in the router's settings unless a game console or app needs it."
        ),
        // SSH is a normal admin tool on computers, servers and NAS boxes; on a camera or smart
        // device it usually ships with a default password nobody changes. Low.
        SecurityRule(
            id: "ssh-iot", ports: [22], service: "SSH", deviceTypes: [.camera, .iot], severity: .low,
            explanation: "Cameras and smart devices rarely need remote login, and their SSH often keeps the maker's default password.",
            remedy: "Turn SSH off if the device allows it, or change its password."
        )
    ]

    /// Shared by the MySQL and PostgreSQL rules: both are login-protected databases on the LAN.
    static let databaseExplanation =
        "A database listening on the network can be reached by every device on it, and weak passwords can be guessed."
    static let databaseRemedy = "Bind the database to the device itself unless other devices need it, and use strong passwords."

    /// Every TCP port a rule reads, for the quick scan to probe.
    public static let ports: Set<Int> = rules.reduce(into: []) { $0.formUnion($1.ports) }

    /// The findings on `devices`, ranked: highest severity first, then rule order, then device
    /// name and port. Only ports in each device's `openPorts` count.
    public static func findings(for devices: [LocalDevice]) -> [SecurityFinding] {
        let found = devices.flatMap { device in
            Set(device.openPorts ?? []).sorted().flatMap { port in
                rules.filter { $0.applies(port: port, deviceType: device.deviceType) }.map { rule in
                    finding(rule, port: port, device: device)
                }
            }
        }
        let order = Dictionary(uniqueKeysWithValues: rules.enumerated().map { ($1.id, $0) })
        return found.sorted { lhs, rhs in
            if lhs.severity != rhs.severity {
                return lhs.severity > rhs.severity
            }
            if lhs.ruleID != rhs.ruleID {
                return order[lhs.ruleID, default: 0] < order[rhs.ruleID, default: 0]
            }
            let names = lhs.deviceName.localizedStandardCompare(rhs.deviceName)
            if names != .orderedSame {
                return names == .orderedAscending
            }
            if lhs.port != rhs.port {
                return lhs.port < rhs.port
            }
            return lhs.deviceID.uuidString < rhs.deviceID.uuidString
        }
    }

    private static func finding(_ rule: SecurityRule, port: Int, device: LocalDevice) -> SecurityFinding {
        SecurityFinding(
            id: "\(device.id.uuidString)-\(rule.id)-\(port)",
            deviceID: device.id,
            deviceName: device.displayName,
            port: port,
            ruleID: rule.id,
            service: rule.service,
            severity: rule.severity(for: device.deviceType),
            title: rule.title(port: port),
            explanation: rule.explanation,
            remedy: rule.remedy
        )
    }
}
