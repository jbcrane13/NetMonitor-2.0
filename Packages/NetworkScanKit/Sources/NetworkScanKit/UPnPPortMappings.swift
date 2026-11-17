import Foundation
import os.log

/// Counts and fault codes only, never addresses or URLs.
private let logger = Logger(subsystem: "com.netmonitor.scankit", category: "UPnPPortMappings")

// MARK: - Model

/// One port forward the router opened through UPnP (#400). Read-only.
public struct UPnPPortMapping: Sendable, Equatable {
    public enum TransportProtocol: String, Sendable {
        case tcp = "TCP"
        case udp = "UDP"
    }

    public let externalPort: UInt16
    public let transportProtocol: TransportProtocol
    /// The LAN address the router forwards to.
    public let internalClient: String
    public let internalPort: UInt16
    public let description: String
    /// Seconds left; 0 means permanent.
    public let leaseSeconds: Int
    public let isEnabled: Bool
    /// Only this remote host may use the forward; nil means any.
    public let remoteHost: String?

    public init(
        externalPort: UInt16,
        transportProtocol: TransportProtocol,
        internalClient: String,
        internalPort: UInt16,
        description: String,
        leaseSeconds: Int,
        isEnabled: Bool,
        remoteHost: String?
    ) {
        self.externalPort = externalPort
        self.transportProtocol = transportProtocol
        self.internalClient = internalClient
        self.internalPort = internalPort
        self.description = description
        self.leaseSeconds = leaseSeconds
        self.isEnabled = isEnabled
        self.remoteHost = remoteHost
    }
}

/// What reading the router's port forwards found.
public enum UPnPPortMappingReport: Sendable, Equatable {
    /// No device answered the SSDP search (on iPhone, likely the missing multicast
    /// entitlement, #381).
    case noGateway
    /// Devices answered, but none offers a WANIPConnection or WANPPPConnection service.
    case noWANService
    /// The forwards read. `isComplete` is true only when the router ended the list with an
    /// end-of-list fault; it is false when reading stopped early (a timeout, an unreadable
    /// reply, any other fault such as an auth error, or the entry cap).
    case mappings([UPnPPortMapping], isComplete: Bool)
}

/// A router's WAN connection service, the one that lists port forwards. It can only be
/// made through validation: the type is WANIPConnection or WANPPPConnection, and the
/// control URL passes the same LAN rules as a `LOCATION` (plain http, an IPv4 literal in
/// the scan subnet, port 1...65535). It is the only destination SOAP is sent to.
struct UPnPWANService: Sendable, Equatable {
    let serviceType: String
    let controlURL: URL

    init?(serviceType: String, controlURL: String, subnetFilter: (String) -> Bool) {
        guard UPnPWANServiceParser.isWANConnectionType(serviceType),
              let url = UPnPDescriptionFetcher.descriptionURL(fromLocation: controlURL, subnetFilter: subnetFilter) else {
            return nil
        }
        self.serviceType = serviceType
        self.controlURL = url
    }
}

// MARK: - Service discovery

enum UPnPWANServiceParser {
    /// The only service types used: they are echoed into a header and the SOAP envelope.
    static func isWANConnectionType(_ type: String) -> Bool {
        type.range(of: #"^urn:schemas-upnp-org:service:WAN(IP|PPP)Connection:[0-9]{1,3}$"#, options: .regularExpression) != nil
    }

    /// WANIPConnection / WANPPPConnection services anywhere in a description (they sit in
    /// nested devices), with `controlURL` resolved against `URLBase` or the description's
    /// own URL and kept only when it passes the same LAN rules as a `LOCATION`.
    static func wanServices(in data: Data, descriptionURL: URL, subnetFilter: (String) -> Bool) -> [UPnPWANService] {
        guard !data.isEmpty, data.count <= UPnPDeviceDescription.maxBytes else { return [] }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let collector = ServiceCollector()
        parser.delegate = collector
        guard parser.parse() else { return [] }

        let base = collector.urlBase.flatMap { URL(string: $0) } ?? descriptionURL
        return collector.services.compactMap { type, control in
            guard let resolved = URL(string: control, relativeTo: base)?.absoluteURL else { return nil }
            return UPnPWANService(serviceType: type, controlURL: resolved.absoluteString, subnetFilter: subnetFilter)
        }
    }
}

/// Collects `URLBase` and every `<service>`'s type and control URL. Used synchronously.
private final class ServiceCollector: NSObject, XMLParserDelegate {
    private(set) var urlBase: String?
    private(set) var services: [(type: String, control: String)] = []

    private var path: [String] = []
    private var text = ""
    private var serviceType: String?
    private var controlURL: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        path.append(name)
        text = ""
        if name == "service" {
            serviceType = nil
            controlURL = nil
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(bytes: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = path.count >= 2 ? path[path.count - 2] : nil
        switch (name, parent) {
        case ("URLBase", "root"): urlBase = value
        case ("serviceType", "service"): serviceType = value
        case ("controlURL", "service"): controlURL = value
        case ("service", _):
            if let serviceType, let controlURL, !controlURL.isEmpty {
                services.append((serviceType, controlURL))
            }
        default: break
        }
        if !path.isEmpty {
            path.removeLast()
        }
        text = ""
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

// MARK: - SOAP

enum UPnPPortMappingSOAP {
    /// The only action ever sent. Read-only.
    static let action = "GetGenericPortMappingEntry"
    static let responseElement = "GetGenericPortMappingEntryResponse"
    static let maxDescriptionLength = 128
    /// Faults that mean "no entry at this index", the normal end of the list: 713
    /// SpecifiedArrayIndexInvalid (the IGD spec's code) and 714 NoSuchEntryInArray, which
    /// some routers send instead. Any other fault (401 Invalid Action, 501 Action Failed, an
    /// auth error) stops the read with an incomplete list.
    static let endOfListFaultCodes: Set<Int> = [713, 714]

    /// The SOAPAction header value and the envelope for one entry index.
    static func request(service: UPnPWANService, index: Int) -> (soapAction: String, body: Data) {
        let envelope = """
        <?xml version="1.0"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(service.serviceType)"><NewPortMappingIndex>\(index)</NewPortMappingIndex></u:\(action)></s:Body>\
        </s:Envelope>
        """
        return ("\(service.serviceType)#\(action)", Data(envelope.utf8))
    }

    /// What one `GetGenericPortMappingEntry` call answered.
    enum Reply: Equatable {
        case entry(UPnPPortMapping)
        /// A SOAP fault, with its UPnP error code when the reply carries a numeric one.
        /// Only ``endOfListFaultCodes`` end the list as complete.
        case fault(code: Int?)
        /// No usable answer: a timeout, a malformed reply or bad values.
        case unreadable
    }

    static func parse(status: Int, body: Data) -> Reply {
        guard let reply = SOAPReplyParser.parse(body) else { return .unreadable }
        switch reply {
        case let .fault(errorCode):
            return .fault(code: errorCode.flatMap { Int($0) })
        case let .response(fields):
            guard status == 200 else { return .unreadable }
            return entry(from: fields)
        }
    }

    private static func entry(from fields: [String: String]) -> Reply {
        guard let external = fields["NewExternalPort"].flatMap(port),
              let transport = fields["NewProtocol"].flatMap({ UPnPPortMapping.TransportProtocol(rawValue: $0.uppercased()) }),
              let client = fields["NewInternalClient"], isValidIPv4Address(client),
              let internalPort = fields["NewInternalPort"].flatMap(port) else {
            return .unreadable
        }
        let lease = fields["NewLeaseDuration"].flatMap { Int($0) } ?? 0
        guard lease >= 0 else { return .unreadable }
        let remote = fields["NewRemoteHost"].flatMap { $0.isEmpty ? nil : $0 }
        return .entry(UPnPPortMapping(
            externalPort: external,
            transportProtocol: transport,
            internalClient: client,
            internalPort: internalPort,
            description: String((fields["NewPortMappingDescription"] ?? "").prefix(maxDescriptionLength)),
            leaseSeconds: lease,
            isEnabled: fields["NewEnabled"].map { $0 == "1" || $0.lowercased() == "true" } ?? true,
            remoteHost: remote
        ))
    }

    private static func port(_ text: String) -> UInt16? {
        guard let value = Int(text), (1...65_535).contains(value) else { return nil }
        return UInt16(exactly: value)
    }
}

/// Reads a SOAP reply by its structure, not by element names found anywhere. Only these
/// count: the direct leaf children of `Envelope/Body/GetGenericPortMappingEntryResponse`,
/// or `Envelope/Body/Fault` with its code at `Fault/detail/UPnPError/errorCode`. The
/// Header is ignored. Nil for malformed XML, a Body without exactly one of those, a
/// duplicate field or error code, or a field with child elements. Used synchronously.
private final class SOAPReplyParser: NSObject, XMLParserDelegate {
    enum Result {
        case response([String: String])
        case fault(errorCode: String?)
    }

    private enum Kind { case response, fault }

    private static let errorCodePath = ["Envelope", "Body", "Fault", "detail", "UPnPError", "errorCode"]

    private var path: [String] = []
    private var text = ""
    private var isInvalid = false
    private var bodyCount = 0
    private var kind: Kind?
    private var fields: [String: String] = [:]
    private var errorCode: String?

    static func parse(_ data: Data) -> Result? {
        guard !data.isEmpty, data.count <= UPnPDeviceDescription.maxBytes else { return nil }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let collector = SOAPReplyParser()
        parser.delegate = collector
        guard parser.parse(), !collector.isInvalid, let kind = collector.kind else { return nil }
        switch kind {
        case .response: return .response(collector.fields)
        case .fault: return .fault(errorCode: collector.errorCode)
        }
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        let name = localName(elementName)
        let inBody = path.count >= 2 && path[1] == "Body"
        switch path.count {
        case 0:
            if name != "Envelope" {
                isInvalid = true
            }
        case 1:
            if name == "Body" {
                bodyCount += 1
                if bodyCount > 1 {
                    isInvalid = true
                }
            }
        case 2 where inBody:
            // Exactly one child of Body: the response or a fault.
            if kind != nil {
                isInvalid = true
            } else if name == UPnPPortMappingSOAP.responseElement {
                kind = .response
            } else if name == "Fault" {
                kind = .fault
            } else {
                isInvalid = true
            }
        default:
            // A response field is a leaf: an element inside one is not trusted.
            if inBody, kind == .response, path.count >= 4 {
                isInvalid = true
            }
        }
        path.append(name)
        text = ""
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(bytes: CDATABlock, encoding: .utf8) ?? ""
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = localName(elementName)
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.count == 4, path[1] == "Body", kind == .response {
            if fields[name] != nil {
                isInvalid = true
            }
            fields[name] = value
        } else if path == Self.errorCodePath {
            if errorCode != nil {
                isInvalid = true
            }
            errorCode = value
        }
        if !path.isEmpty {
            path.removeLast()
        }
        text = ""
    }

    private func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }
}

// MARK: - Reading

public enum UPnPPortMappingReader {
    /// Most entries read from one router.
    public static let maxEntries = 128

    /// One `GetGenericPortMappingEntry` call: status and body, or nil for no usable reply
    /// (timeout, refused).
    typealias Call = @Sendable (_ service: UPnPWANService, _ index: Int) async -> (status: Int, body: Data)?
    /// Fetches a description document.
    typealias Fetch = @Sendable (_ url: URL) async -> Data?
    /// SSDP search: responder IP to its `LOCATION`s.
    typealias Search = @Sendable () async -> [String: [String]]

    /// Reads the forwards of the router on the scan's LAN, read-only. Only
    /// `GetGenericPortMappingEntry` is ever sent.
    public static func read(localIP: String?, subnetFilter: @escaping @Sendable (String) -> Bool) async -> UPnPPortMappingReport {
        await read(
            subnetFilter: subnetFilter,
            search: { await SSDPSocketSearch.search(localIP: localIP) },
            fetch: { await UPnPDescriptionFetcher.fetch($0) },
            call: { await UPnPDescriptionFetcher.getGenericPortMappingEntry(index: $1, service: $0) }
        )
    }

    static func read(
        subnetFilter: @escaping @Sendable (String) -> Bool,
        search: Search,
        fetch: Fetch,
        call: Call,
        maxEntries: Int = maxEntries
    ) async -> UPnPPortMappingReport {
        let responders = await search().filter { subnetFilter($0.key) }
        guard !responders.isEmpty else { return .noGateway }
        guard let service = await findWANService(responders, subnetFilter: subnetFilter, fetch: fetch) else {
            logger.notice("UPnP: \(responders.count, privacy: .public) responders, no WAN connection service")
            return .noWANService
        }
        return await readEntries(service: service, call: call, maxEntries: maxEntries)
    }

    /// The first WAN connection service among the responders' descriptions. Responders
    /// are tried in address order; each `LOCATION` is fetched at most once.
    static func findWANService(
        _ responders: [String: [String]],
        subnetFilter: @escaping @Sendable (String) -> Bool,
        fetch: Fetch
    ) async -> UPnPWANService? {
        var seen: Set<URL> = []
        for ip in responders.keys.sorted(by: { $0.ipSortKey < $1.ipSortKey }) {
            for location in responders[ip] ?? [] {
                guard !Task.isCancelled else { return nil }
                guard let url = UPnPDescriptionFetcher.descriptionURL(fromLocation: location, subnetFilter: subnetFilter),
                      seen.insert(url).inserted,
                      let data = await fetch(url) else { continue }
                if let service = UPnPWANServiceParser.wanServices(in: data, descriptionURL: url, subnetFilter: subnetFilter).first {
                    return service
                }
            }
        }
        return nil
    }

    /// Calls index 0, 1, … until the router sends an end-of-list fault (complete), or
    /// until any other fault, a call with no usable answer, the cap or cancellation
    /// (incomplete).
    static func readEntries(service: UPnPWANService, call: Call, maxEntries: Int = maxEntries) async -> UPnPPortMappingReport {
        var mappings: [UPnPPortMapping] = []
        for index in 0..<maxEntries {
            guard !Task.isCancelled else { return .mappings(mappings, isComplete: false) }
            guard let reply = await call(service, index) else {
                logger.notice("UPnP: no reply at entry \(index, privacy: .public)")
                return .mappings(mappings, isComplete: false)
            }
            switch UPnPPortMappingSOAP.parse(status: reply.status, body: reply.body) {
            case let .entry(mapping):
                mappings.append(mapping)
            case let .fault(code):
                let isEnd = code.map { UPnPPortMappingSOAP.endOfListFaultCodes.contains($0) } ?? false
                logger.info("UPnP: \(mappings.count, privacy: .public) forwards, fault \(code ?? -1, privacy: .public), end \(isEnd, privacy: .public)")
                return .mappings(mappings, isComplete: isEnd)
            case .unreadable:
                logger.notice("UPnP: unreadable reply at entry \(index, privacy: .public), status \(reply.status, privacy: .public)")
                return .mappings(mappings, isComplete: false)
            }
        }
        logger.notice("UPnP: entry cap \(maxEntries, privacy: .public) reached")
        return .mappings(mappings, isComplete: false)
    }
}
