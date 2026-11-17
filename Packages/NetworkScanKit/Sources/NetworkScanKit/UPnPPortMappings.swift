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
    /// The forwards read. `isComplete` is false when reading stopped early (a timeout,
    /// an unreadable reply or the entry cap), so the list may be missing entries.
    case mappings([UPnPPortMapping], isComplete: Bool)
}

/// A router's WAN connection service, the one that lists port forwards.
public struct UPnPWANService: Sendable, Equatable {
    public let serviceType: String
    public let controlURL: URL

    public init(serviceType: String, controlURL: URL) {
        self.serviceType = serviceType
        self.controlURL = controlURL
    }
}

// MARK: - Service discovery

public enum UPnPWANServiceParser {
    /// The only service types used: they are echoed into a header and the SOAP envelope.
    static func isWANConnectionType(_ type: String) -> Bool {
        type.range(of: #"^urn:schemas-upnp-org:service:WAN(IP|PPP)Connection:[0-9]{1,3}$"#, options: .regularExpression) != nil
    }

    /// WANIPConnection / WANPPPConnection services anywhere in a description (they sit in
    /// nested devices), with `controlURL` resolved against `URLBase` or the description's
    /// own URL and kept only when it passes the same LAN rules as a `LOCATION`.
    public static func wanServices(in data: Data, descriptionURL: URL, subnetFilter: (String) -> Bool) -> [UPnPWANService] {
        guard !data.isEmpty, data.count <= UPnPDeviceDescription.maxBytes else { return [] }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let collector = ServiceCollector()
        parser.delegate = collector
        guard parser.parse() else { return [] }

        let base = collector.urlBase.flatMap { URL(string: $0) } ?? descriptionURL
        return collector.services.compactMap { type, control in
            guard isWANConnectionType(type),
                  let resolved = URL(string: control, relativeTo: base)?.absoluteURL,
                  let url = UPnPDescriptionFetcher.descriptionURL(fromLocation: resolved.absoluteString, subnetFilter: subnetFilter) else {
                return nil
            }
            return UPnPWANService(serviceType: type, controlURL: url)
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

public enum UPnPPortMappingSOAP {
    public static let action = "GetGenericPortMappingEntry"
    static let maxDescriptionLength = 128

    /// The SOAPAction header value and the envelope for one entry index.
    static func request(serviceType: String, index: Int) -> (soapAction: String, body: Data) {
        let envelope = """
        <?xml version="1.0"?>\
        <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
        <s:Body><u:\(action) xmlns:u="\(serviceType)"><NewPortMappingIndex>\(index)</NewPortMappingIndex></u:\(action)></s:Body>\
        </s:Envelope>
        """
        return ("\(serviceType)#\(action)", Data(envelope.utf8))
    }

    /// What one `GetGenericPortMappingEntry` call answered.
    enum Reply: Equatable {
        case entry(UPnPPortMapping)
        /// A SOAP fault: the router has no entry at this index (713 is
        /// SpecifiedArrayIndexInvalid). Some routers send other codes, so any fault ends
        /// the list.
        case fault(code: Int?)
        /// No usable answer: a timeout, a malformed reply or bad values.
        case unreadable
    }

    static func parse(status: Int, body: Data) -> Reply {
        let fields = ElementTextCollector.collect(body)
        guard let fields else { return .unreadable }
        if fields["Fault"] != nil || status == 500 {
            guard fields["Fault"] != nil else { return .unreadable }
            return .fault(code: fields["errorCode"].flatMap { Int($0) })
        }
        guard status == 200,
              let external = fields["NewExternalPort"].flatMap(port),
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

/// Text of each leaf element by local name (first one wins); `Fault` is recorded as
/// present. Nil for malformed XML.
private final class ElementTextCollector: NSObject, XMLParserDelegate {
    private var values: [String: String] = [:]
    private var text = ""

    static func collect(_ data: Data) -> [String: String]? {
        guard !data.isEmpty, data.count <= UPnPDeviceDescription.maxBytes else { return nil }
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        let collector = ElementTextCollector()
        parser.delegate = collector
        return parser.parse() ? collector.values : nil
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        if localName(elementName) == "Fault" {
            values["Fault"] = values["Fault"] ?? ""
        }
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
        if values[name] == nil {
            values[name] = text.trimmingCharacters(in: .whitespacesAndNewlines)
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

    /// One SOAP call: status and body, or nil for no usable reply (timeout, refused).
    typealias Call = @Sendable (_ url: URL, _ soapAction: String, _ body: Data) async -> (status: Int, body: Data)?
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
            call: { await UPnPDescriptionFetcher.postSOAP($0, soapAction: $1, body: $2) }
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

    /// Calls index 0, 1, … until the router faults (end of list, complete) or a call
    /// gives no usable answer, the cap is reached or the task is cancelled (incomplete).
    static func readEntries(service: UPnPWANService, call: Call, maxEntries: Int = maxEntries) async -> UPnPPortMappingReport {
        var mappings: [UPnPPortMapping] = []
        for index in 0..<maxEntries {
            guard !Task.isCancelled else { return .mappings(mappings, isComplete: false) }
            let request = UPnPPortMappingSOAP.request(serviceType: service.serviceType, index: index)
            guard let reply = await call(service.controlURL, request.soapAction, request.body) else {
                logger.notice("UPnP: no reply at entry \(index, privacy: .public)")
                return .mappings(mappings, isComplete: false)
            }
            switch UPnPPortMappingSOAP.parse(status: reply.status, body: reply.body) {
            case let .entry(mapping):
                mappings.append(mapping)
            case let .fault(code):
                logger.info("UPnP: \(mappings.count, privacy: .public) forwards, end fault \(code ?? -1, privacy: .public)")
                return .mappings(mappings, isComplete: true)
            case .unreadable:
                logger.notice("UPnP: unreadable reply at entry \(index, privacy: .public), status \(reply.status, privacy: .public)")
                return .mappings(mappings, isComplete: false)
            }
        }
        logger.notice("UPnP: entry cap \(maxEntries, privacy: .public) reached")
        return .mappings(mappings, isComplete: false)
    }
}
