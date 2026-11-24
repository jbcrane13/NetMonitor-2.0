import Foundation

/// Turns each tool's result into an `InsightRequest`. Pure: every figure in a request comes
/// from the result passed in, and every judgement is computed here rather than by the model.
public enum ToolInsightBuilder {
    // MARK: - SSL certificate

    /// - Parameters:
    ///   - now: the time expiry is judged against. `daysUntilExpiry` can't tell an expired
    ///     certificate from one expiring today, because the service clamps it to zero.
    ///   - calendar: reads dates the way the screen shows them.
    public static func sslCertificate(_ info: SSLCertificateInfo, now: Date = Date(), calendar: Calendar = .current) -> InsightRequest {
        let isExpired = info.validTo < now
        var facts = [
            "Issuer: \(info.issuer)",
            "Subject: \(info.subject)",
            "Valid from: \(day(info.validFrom, calendar))",
            "Valid to: \(day(info.validTo, calendar))",
            isExpired ? "Expired: yes" : "Days until expiry: \(info.daysUntilExpiry)"
        ]
        facts.append("Certificate valid: \(info.isValid ? "yes" : "no")")

        var observations: [String] = []
        if isExpired {
            let days = calendar.dateComponents([.day], from: info.validTo, to: now).day ?? 0
            observations.append(
                days >= 1
                    ? "The certificate expired \(plural(days, "day")) ago; browsers will show a warning."
                    : "The certificate expired earlier today; browsers will show a warning."
            )
        } else if info.daysUntilExpiry <= 14 {
            observations.append("The certificate expires in \(plural(info.daysUntilExpiry, "day")) and should be renewed now.")
        } else if info.daysUntilExpiry <= 30 {
            observations.append("The certificate expires in \(plural(info.daysUntilExpiry, "day")); plan the renewal.")
        }
        if !info.isValid, !isExpired {
            observations.append("The certificate did not pass validation even though it has not expired.")
        }
        return InsightRequest(subject: "SSL certificate check for \(info.domain)", facts: facts, observations: observations)
    }

    // MARK: - Port scan

    /// What an open port usually means, for the ports worth a remark. The scan only proves
    /// the port accepts a connection, so every note says "usually".
    static let portNotes: [Int: String] = [
        21: "is usually FTP, file transfer without encryption; prefer SFTP if the device offers it.",
        22: "is usually SSH, encrypted remote login, normal on computers and network equipment.",
        23: "is usually Telnet, remote login without encryption; turn it off if it is not needed.",
        53: "is usually DNS, normal on a router.",
        80: "is usually an unencrypted web page, often the device's settings page.",
        443: "is usually an encrypted web page, often the device's settings page.",
        445: "is usually Windows file sharing, normal on computers and network storage.",
        554: "is usually video streaming (RTSP), normal for cameras and media devices.",
        631: "is usually network printing, normal on printers.",
        3389: "is usually Windows Remote Desktop; make sure it is meant to be on.",
        5900: "is usually screen sharing (VNC); make sure it is meant to be on.",
        9100: "is usually network printing, normal on printers.",
        62078: "is usually the sync service that iPhones and iPads keep open."
    ]

    /// - Parameter scannedCount: how many ports were scanned, when `results` holds only the open ones.
    public static func portScan(host: String, results: [PortScanResult], scannedCount: Int? = nil) -> InsightRequest {
        let open = results.filter { $0.state == .open }.sorted { $0.port < $1.port }
        let closed = results.count { $0.state == .closed }
        let filtered = results.count { $0.state == .filtered }
        func label(_ result: PortScanResult) -> String {
            result.serviceName.map { "\(result.port) (usually \($0))" } ?? "\(result.port)"
        }

        var openText = open.prefix(listLimit).map(label).joined(separator: ", ")
        if open.count > listLimit {
            openText += ", and \(open.count - listLimit) more"
        }
        var facts = ["Number of ports scanned: \(scannedCount ?? results.count)", open.isEmpty ? "Open ports: none" : "Open ports (\(open.count)): \(openText)"]
        if closed > 0 {
            facts.append("Number of closed ports: \(closed)")
        }
        if filtered > 0 {
            facts.append("Number of filtered ports (no answer, usually a firewall): \(filtered)")
        }
        if let scannedCount, scannedCount > results.count {
            facts.append("Number of ports that did not accept a connection: \(scannedCount - results.count)")
        }

        if !open.isEmpty {
            facts.append("The scan only checked whether each port accepts a connection; service names are the usual use of that port number.")
        }

        var observations = open.compactMap { result in
            portNotes[result.port].map { "Port \(result.port) \($0)" }
        }
        if open.isEmpty {
            observations.append("No scanned port accepted a connection.")
        }
        return InsightRequest(subject: "Port scan of \(host)", facts: facts, observations: Array(observations.prefix(observationLimit)))
    }

    // MARK: - Traceroute and GeoTrace

    /// - Parameter places: a location per hop number, when the trace was geolocated.
    public static func traceroute(host: String, hops: [TracerouteHop], places: [Int: String] = [:]) -> InsightRequest {
        var facts = hops.prefix(listLimit).map { hop -> String in
            guard !hop.isTimeout, let address = hop.ipAddress ?? hop.hostname else { return "Hop \(hop.hopNumber): no reply" }
            var line = "Hop \(hop.hopNumber): \(address)"
            if let time = hop.averageTime {
                line += ", \(String(format: "%.1f", time)) ms"
            }
            if let place = places[hop.hopNumber] {
                line += ", \(place)"
            }
            return line
        }
        if hops.count > listLimit {
            facts.append("\(hops.count - listLimit) more hops not listed")
        }

        let replied = hops.filter { !$0.isTimeout && ($0.ipAddress ?? $0.hostname) != nil }
        var observations: [String] = []
        if let last = hops.last, !last.isTimeout, let finalTime = last.averageTime, let address = last.ipAddress ?? last.hostname {
            // Arrival is only certain when the last hop is the host that was asked for.
            let arrived = last.ipAddress == host || last.hostname == host
            let finalText = String(format: "%.1f", finalTime)
            observations.append(
                arrived
                    ? "The trace reached the destination in \(plural(hops.count, "hop")), at \(finalText) ms."
                    : "The last hop to reply was hop \(last.hopNumber) (\(address)), at \(finalText) ms."
            )
            let silent = hops.count - replied.count
            if silent > 0 {
                let verb = silent == 1 ? "1 hop did not reply" : "\(silent) hops did not reply"
                observations.append("\(verb). Routers often ignore these probes; it is not a fault when later hops answer.")
            }
            let slowest = replied.dropLast().max { ($0.averageTime ?? 0) < ($1.averageTime ?? 0) }
            if let slowest, let time = slowest.averageTime, time > finalTime * 2, time - finalTime >= 20 {
                observations.append(
                    "Hop \(slowest.hopNumber) answered slower (\(String(format: "%.1f", time)) ms) than " +
                        "\(arrived ? "the destination" : "the last hop") (\(finalText) ms), " +
                        "so the delay is that router answering probes slowly, not a slow path."
                )
            }
        } else if let lastReply = replied.last, let address = lastReply.ipAddress ?? lastReply.hostname {
            observations.append("The trace did not reach the destination. The last hop to reply was hop \(lastReply.hopNumber) (\(address)).")
        } else if !hops.isEmpty {
            observations.append("No hop replied, so the trace shows nothing about the path.")
        }
        return InsightRequest(subject: "Traceroute to \(host)", facts: facts, observations: observations)
    }

    // MARK: - DNS

    /// - Parameter allTypes: true when every record type was queried; `result.queryType` is then
    ///   a placeholder and not what was asked.
    public static func dnsLookup(_ result: DNSQueryResult, allTypes: Bool = false) -> InsightRequest {
        // Each name stands whole after its label, so an answer may repeat it past
        // `InsightTextFilter`, which refuses a domain inside a longer value (#457).
        var facts = ["Name looked up: \(result.domain)", "DNS server: \(result.server)", "Query time: \(number(result.queryTime)) ms"]
        facts += result.records.prefix(recordLimit).map { record in
            let value = record.value.count > valueLimit ? record.value.prefix(valueLimit) + "…" : record.value
            var label = "\(record.type.rawValue) record"
            if let priority = record.priority {
                label += ", priority \(priority)"
            }
            return "\(label), TTL \(record.ttl) s: \(value)"
        }
        if result.records.count > recordLimit {
            facts.append("\(result.records.count - recordLimit) more records not listed")
        }

        var observations: [String] = []
        if result.records.isEmpty {
            observations.append(
                allTypes ? "The name has no records of any type that was queried." : "The name has no \(result.queryType.rawValue) records."
            )
        }
        if result.queryTime >= 300 {
            observations.append("The answer took \(number(result.queryTime)) ms, which is slow for a DNS lookup.")
        }
        return InsightRequest(
            subject: "DNS lookup of \(allTypes ? "all record types" : "\(result.queryType.rawValue) records") for \(result.domain)",
            facts: facts,
            observations: observations
        )
    }

    /// For lookups that return only answer values, as the macOS tool's `dig +short` does.
    public static func dnsAnswers(domain: String, recordType: DNSRecordType, answers: [String]) -> InsightRequest {
        // One answer per fact, each whole after its label, as in `dnsLookup` (#457).
        var facts = ["Name looked up: \(domain)", "Number of answers: \(answers.count)"]
        facts += answers.prefix(recordLimit).map { "Answer: \($0)" }
        if answers.count > recordLimit {
            facts.append("\(answers.count - recordLimit) more answers not listed")
        }
        return InsightRequest(
            subject: "DNS lookup of \(recordType.rawValue) records for \(domain)",
            facts: facts
        )
    }

    // MARK: - WHOIS

    public static func whois(_ result: WHOISResult, now: Date = Date(), calendar: Calendar = .current) -> InsightRequest {
        var facts: [String] = []
        func add(_ label: String, _ value: String?) {
            if let value, !value.isEmpty {
                facts.append("\(label): \(value)")
            }
        }
        add("Registrar", result.registrar)
        add("Registered", result.creationDate.map { day($0, calendar) })
        add("Expires", result.expirationDate.map { day($0, calendar) })
        var nameServers = result.nameServers.prefix(4).joined(separator: ", ")
        if result.nameServers.count > 4 {
            nameServers += ", and \(result.nameServers.count - 4) more"
        }
        add("Name servers", nameServers)
        add("Owner", result.registrantOrganization)
        add("DNSSEC", result.dnssec)
        add("Network range", result.networkRange)
        add("Network name", result.networkName)
        add("Network owner", result.networkOrganization)
        add("Country", result.networkCountry ?? result.registrantCountry)
        add("ASN", result.asn)

        var observations: [String] = []
        if let created = result.creationDate {
            let years = calendar.dateComponents([.year], from: created, to: now).year ?? 0
            observations.append(
                years >= 1 ? "The domain has been registered for \(plural(years, "year"))." : "The domain was registered less than a year ago."
            )
        }
        if let expires = result.expirationDate {
            let days = Int((expires.timeIntervalSince(now) / 86400).rounded(.down))
            if days < 0 {
                observations.append("The registration expired \(plural(-days, "day")) ago.")
            } else if days <= 30 {
                observations.append("The registration expires in \(plural(days, "day")); if it is not renewed the domain stops working.")
            }
        }
        if result.registrar != nil, result.registrantOrganization == nil {
            observations.append("The owner's details are not published, which is normal privacy protection.")
        }
        return InsightRequest(subject: "WHOIS lookup for \(result.query)", facts: facts, observations: observations)
    }

    // MARK: - Speed test

    public static func speedTest(_ data: SpeedTestData) -> InsightRequest {
        var facts = [
            "Download: \(number(data.downloadSpeed)) Mbps",
            "Upload: \(number(data.uploadSpeed)) Mbps",
            "Latency: \(number(data.latency)) ms"
        ]
        if let jitter = data.jitter {
            facts.append("Jitter: \(number(jitter)) ms")
        }
        if let server = data.serverName {
            facts.append("Test server: \(server)")
        }

        var observations: [String] = []
        switch data.downloadSpeed {
        case ..<5: observations.append("Download is below 5 Mbps; HD video will buffer.")
        case ..<25: observations.append("Download is enough for HD video on one or two devices.")
        case ..<100: observations.append("Download is enough for 4K streaming and video calls.")
        default: observations.append("Download is fast enough for several 4K streams at once.")
        }
        if data.uploadSpeed < 1 {
            observations.append("Upload is below 1 Mbps; video calls will struggle to send your picture.")
        } else if data.downloadSpeed / data.uploadSpeed >= 10 {
            let ratio = Int((data.downloadSpeed / data.uploadSpeed).rounded())
            observations.append(
                "Upload is about \(ratio) times slower than download, which is typical of cable connections " +
                    "and limits backups and sending large files."
            )
        }
        if data.latency >= 100 {
            observations.append("Latency of \(number(data.latency)) ms is high and will make calls and games feel delayed.")
        }
        if let jitter = data.jitter, jitter >= 30 {
            observations.append("Jitter of \(number(jitter)) ms is high, so calls may break up.")
        }
        if data.latency < 50 {
            if let jitter = data.jitter {
                if jitter < 10 {
                    observations.append("Latency and jitter are low, good for video calls and gaming.")
                }
            } else {
                observations.append("Latency is low, good for video calls and gaming.")
            }
        }
        return InsightRequest(subject: "Internet speed test", facts: facts, observations: observations)
    }

    // MARK: - Health score

    /// - Parameter checks: the health checks shown with the score; the ones that warn are stated.
    public static func healthScore(_ score: NetworkHealthScore, checks: [HealthCheck] = []) -> InsightRequest {
        var facts = ["Score: \(score.score) out of 100, grade \(score.grade)"]
        var observations: [String] = []
        if let latency = score.latencyMs {
            facts.append("Latency: \(number(latency)) ms")
            if latency >= 100 {
                observations.append("Latency of \(number(latency)) ms is high.")
            }
        }
        if let loss = score.packetLoss {
            let percent = Int((loss * 100).rounded())
            facts.append("Packet loss: \(percent)%")
            if loss >= 0.02 {
                observations.append("Packet loss of \(percent)% is enough to disrupt calls and streaming.")
            }
        }
        if let dns = score.details["dns"] {
            facts.append("DNS response: \(dns)")
        }
        observations += checks.filter { $0.status == .warn }.map { "\($0.kind.title): \($0.message)" }
        return InsightRequest(subject: "Network health score", facts: facts, observations: observations)
    }

    // MARK: - Formatting

    /// Longest list of hops or ports a request carries; the on-device model's context is small.
    static let listLimit = 30
    static let recordLimit = 20
    static let observationLimit = 8
    /// Longest record value a request carries; TXT records can run to kilobytes.
    static let valueLimit = 120

    static func day(_ date: Date, _ calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func plural(_ count: Int, _ noun: String) -> String {
        count == 1 ? "1 \(noun)" : "\(count) \(noun)s"
    }

    static func number(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
    }
}
