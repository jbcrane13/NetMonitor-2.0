import Testing
import Foundation
@testable import NetworkScanKit

/// Fixtures are a UniFi gateway's real replies (Nov 2026) with addresses, serials and
/// UUIDs replaced (#400).
@Suite("UPnPPortMappings")
struct UPnPPortMappingsTests {

    static let routerDescription = #"""
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0" configId="1337"><specVersion><major>1</major>
<minor>1</minor>
</specVersion>
<device><deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:2</deviceType>
<friendlyName>UniFi Dream Machine</friendlyName>
<manufacturer>Ubiquiti Networks</manufacturer>
<manufacturerURL>http://ui.com</manufacturerURL>
<modelDescription>UniFi Cloud Gateway Max</modelDescription>
<modelName>UCGMAX</modelName>
<modelNumber>00288d0f</modelNumber>
<modelURL>http://ui.com</modelURL>
<serialNumber>REDACTED</serialNumber>
<UDN>uuid:REDACTED</UDN>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:Layer3Forwarding:1</serviceType>
<serviceId>urn:upnp-org:serviceId:L3Forwarding1</serviceId>
<SCPDURL>/L3F.xml</SCPDURL>
<controlURL>/ctl/L3F</controlURL>
<eventSubURL>/evt/L3F</eventSubURL>
</service>
</serviceList>
<deviceList><device><deviceType>urn:schemas-upnp-org:device:WANDevice:2</deviceType>
<friendlyName>WANDevice</friendlyName>
<manufacturer>MiniUPnP</manufacturer>
<manufacturerURL>https://miniupnp.tuxfamily.org/</manufacturerURL>
<modelDescription>MiniUPnP daemon version 2.3.8</modelDescription>
<modelName>MiniUPnPd</modelName>
<modelNumber>20260924</modelNumber>
<modelURL>https://miniupnp.tuxfamily.org/</modelURL>
<serialNumber>REDACTED</serialNumber>
<UDN>uuid:REDACTED</UDN>
<UPC>000000000000</UPC>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:WANCommonInterfaceConfig:1</serviceType>
<serviceId>urn:upnp-org:serviceId:WANCommonIFC1</serviceId>
<SCPDURL>/WANCfg.xml</SCPDURL>
<controlURL>/ctl/CmnIfCfg</controlURL>
<eventSubURL>/evt/CmnIfCfg</eventSubURL>
</service>
</serviceList>
<deviceList><device><deviceType>urn:schemas-upnp-org:device:WANConnectionDevice:2</deviceType>
<friendlyName>WANConnectionDevice</friendlyName>
<manufacturer>MiniUPnP</manufacturer>
<manufacturerURL>https://miniupnp.tuxfamily.org/</manufacturerURL>
<modelDescription>MiniUPnP daemon version 2.3.8</modelDescription>
<modelName>MiniUPnPd</modelName>
<modelNumber>20260924</modelNumber>
<modelURL>https://miniupnp.tuxfamily.org/</modelURL>
<serialNumber>REDACTED</serialNumber>
<UDN>uuid:REDACTED</UDN>
<UPC>000000000000</UPC>
<serviceList><service><serviceType>urn:schemas-upnp-org:service:WANIPConnection:2</serviceType>
<serviceId>urn:upnp-org:serviceId:WANIPConn1</serviceId>
<SCPDURL>/WANIPCn.xml</SCPDURL>
<controlURL>/ctl/IPConn</controlURL>
<eventSubURL>/evt/IPConn</eventSubURL>
</service>
<service><serviceType>urn:schemas-upnp-org:service:WANIPv6FirewallControl:1</serviceType>
<serviceId>urn:upnp-org:serviceId:WANIPv6Firewall1</serviceId>
<SCPDURL>/WANIP6FC.xml</SCPDURL>
<controlURL>/ctl/IP6FCtl</controlURL>
<eventSubURL>/evt/IP6FCtl</eventSubURL>
</service>
</serviceList>
</device>
</deviceList>
</device>
</deviceList>
<presentationURL>http://192.168.1.1/</presentationURL>
</device>
</root>
"""#

    static let entry = #"""
<?xml version="1.0"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:GetGenericPortMappingEntryResponse xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:2"><NewRemoteHost></NewRemoteHost>
<NewExternalPort>41643</NewExternalPort>
<NewProtocol>UDP</NewProtocol>
<NewInternalPort>41641</NewInternalPort>
<NewInternalClient>192.168.1.17</NewInternalClient>
<NewEnabled>1</NewEnabled>
<NewPortMappingDescription>NAT-PMP 41643 udp</NewPortMappingDescription>
<NewLeaseDuration>4602</NewLeaseDuration>
</u:GetGenericPortMappingEntryResponse>
</s:Body>
</s:Envelope>
"""#

    static let endOfListFault = #"""
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><s:Fault><faultcode>s:Client</faultcode>
<faultstring>UPnPError</faultstring>
<detail><UPnPError xmlns="urn:schemas-upnp-org:control-1-0"><errorCode>713</errorCode>
<errorDescription>SpecifiedArrayIndexInvalid</errorDescription>
</UPnPError>
</detail>
</s:Fault>
</s:Body>
</s:Envelope>
"""#

    private let lan: @Sendable (String) -> Bool = { $0.hasPrefix("192.168.1.") }
    private let descriptionURL = URL(string: "http://192.168.1.1:44695/rootDesc.xml")!

    // MARK: - Service discovery

    @Test("finds the nested WANIPConnection service and resolves its control URL")
    func findsNestedWANService() {
        let services = UPnPWANServiceParser.wanServices(in: Data(Self.routerDescription.utf8), descriptionURL: descriptionURL, subnetFilter: lan)
        #expect(services.map(\.serviceType) == ["urn:schemas-upnp-org:service:WANIPConnection:2"])
        #expect(services.map(\.controlURL.absoluteString) == ["http://192.168.1.1:44695/ctl/IPConn"])
    }

    @Test("URLBase wins over the description URL; off-LAN or https control URLs are dropped")
    func controlURLResolution() {
        func services(_ xml: String) -> [UPnPWANService] {
            UPnPWANServiceParser.wanServices(in: Data(xml.utf8), descriptionURL: descriptionURL, subnetFilter: lan)
        }
        let wan = "urn:schemas-upnp-org:service:WANPPPConnection:1"
        let withBase = "<root><URLBase>http://192.168.1.1:5000/</URLBase><device><serviceList><service><serviceType>\(wan)</serviceType><controlURL>ctl/PPP</controlURL></service></serviceList></device></root>"
        #expect(services(withBase).first?.controlURL.absoluteString == "http://192.168.1.1:5000/ctl/PPP")
        let offLAN = "<root><device><serviceList><service><serviceType>\(wan)</serviceType><controlURL>http://8.8.8.8/ctl</controlURL></service></serviceList></device></root>"
        #expect(services(offLAN).isEmpty)
        let https = "<root><device><serviceList><service><serviceType>\(wan)</serviceType><controlURL>https://192.168.1.1/ctl</controlURL></service></serviceList></device></root>"
        #expect(services(https).isEmpty)
    }

    @Test("only WANIPConnection and WANPPPConnection service types are accepted", arguments: [
        ("urn:schemas-upnp-org:service:WANIPConnection:2", true),
        ("urn:schemas-upnp-org:service:WANPPPConnection:1", true),
        ("urn:schemas-upnp-org:service:WANIPv6FirewallControl:1", false),
        ("urn:schemas-upnp-org:service:WANIPConnection:2\"><x", false),
        ("urn:schemas-upnp-org:service:WANIPConnection:", false)
    ])
    func serviceTypeAllowList(type: String, accepted: Bool) {
        #expect(UPnPWANServiceParser.isWANConnectionType(type) == accepted)
    }

    // MARK: - SOAP request

    private static let ipConnection = "urn:schemas-upnp-org:service:WANIPConnection:2"

    @Test("the HTTP request is a POST of GetGenericPortMappingEntry to the control URL, nothing else")
    func requestBuilding() throws {
        let text = String(decoding: UPnPDescriptionFetcher.portMappingEntryRequest(index: 7, service: Self.service), as: UTF8.self)
        #expect(text.hasPrefix("POST /ctl/IPConn HTTP/1.0\r\n"))
        #expect(text.contains("\r\nHost: 192.168.1.1:44695\r\n"))
        let soapActions = text.components(separatedBy: "\r\n").filter { $0.lowercased().hasPrefix("soapaction:") }
        #expect(soapActions == [#"SOAPAction: "urn:schemas-upnp-org:service:WANIPConnection:2#GetGenericPortMappingEntry""#])
        #expect(text.contains(#"<u:GetGenericPortMappingEntry xmlns:u="urn:schemas-upnp-org:service:WANIPConnection:2">"#))
        #expect(text.contains("<NewPortMappingIndex>7</NewPortMappingIndex>"))
        #expect(!text.contains("AddPortMapping") && !text.contains("DeletePortMapping"))
        let body = try #require(text.components(separatedBy: "\r\n\r\n").last)
        #expect(text.contains("\r\nContent-Length: \(body.utf8.count)\r\n"))
    }

    @Test("no other action can be built: the service type and control URL must pass validation", arguments: [
        ("urn:schemas-upnp-org:service:WANIPConnection:1#AddPortMapping", "http://192.168.1.1/ctl"),
        ("urn:schemas-upnp-org:service:WANIPConnection:1\"\r\nSOAPAction: \"x#DeletePortMapping", "http://192.168.1.1/ctl"),
        ("urn:schemas-upnp-org:service:WANIPConnection:1\"><u:DeletePortMapping", "http://192.168.1.1/ctl"),
        ("urn:schemas-upnp-org:service:Layer3Forwarding:1", "http://192.168.1.1/ctl"),
        (ipConnection, "http://8.8.8.8/ctl"),
        (ipConnection, "https://192.168.1.1/ctl"),
        (ipConnection, "http://router.local/ctl"),
        (ipConnection, "http://192.168.1.1:0/ctl")
    ])
    func serviceValidation(type: String, control: String) {
        #expect(UPnPWANService(serviceType: type, controlURL: control, subnetFilter: { $0.hasPrefix("192.168.1.") }) == nil)
    }

    // MARK: - SOAP replies

    private static func envelope(header: String = "", _ body: String) -> Data {
        let headerElement = header.isEmpty ? "" : "<s:Header>" + header + "</s:Header>"
        return Data(("<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\">" + headerElement
            + "<s:Body>" + body + "</s:Body></s:Envelope>").utf8)
    }

    private static func response(_ fields: String) -> Data {
        envelope("<u:GetGenericPortMappingEntryResponse xmlns:u=\"\(ipConnection)\">\(fields)</u:GetGenericPortMappingEntryResponse>")
    }

    private static func fault(code: String?) -> Data {
        let detail = code.map { "<detail><UPnPError xmlns=\"urn:schemas-upnp-org:control-1-0\"><errorCode>\($0)</errorCode></UPnPError></detail>" } ?? ""
        return envelope("<s:Fault><faultcode>s:Client</faultcode><faultstring>UPnPError</faultstring>\(detail)</s:Fault>")
    }

    private static let validFields = "<NewExternalPort>80</NewExternalPort><NewProtocol>TCP</NewProtocol>"
        + "<NewInternalClient>192.168.1.5</NewInternalClient><NewInternalPort>8080</NewInternalPort>"

    @Test("a real entry parses")
    func parsesEntry() {
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: Data(Self.entry.utf8)) == .entry(UPnPPortMapping(
            externalPort: 41643, transportProtocol: .udp, internalClient: "192.168.1.17", internalPort: 41641,
            description: "NAT-PMP 41643 udp", leaseSeconds: 4602, isEnabled: true, remoteHost: nil
        )))
    }

    @Test("the real end-of-list fault (HTTP 500, 713) parses as a fault")
    func parsesFault() {
        #expect(UPnPPortMappingSOAP.parse(status: 500, body: Data(Self.endOfListFault.utf8)) == .fault(code: 713))
        #expect(UPnPPortMappingSOAP.parse(status: 500, body: Self.fault(code: "606")) == .fault(code: 606))
        #expect(UPnPPortMappingSOAP.parse(status: 500, body: Self.fault(code: nil)) == .fault(code: nil))
        #expect(UPnPPortMappingSOAP.parse(status: 500, body: Self.fault(code: "abc")) == .fault(code: nil))
    }

    @Test("bad values or replies are unreadable, not entries")
    func rejectsBadReplies() {
        func reply(_ external: String = "80", _ proto: String = "TCP", _ client: String = "192.168.1.5", _ lease: String = "0") -> Data {
            Self.response("<NewExternalPort>\(external)</NewExternalPort><NewProtocol>\(proto)</NewProtocol><NewInternalClient>\(client)</NewInternalClient><NewInternalPort>80</NewInternalPort><NewLeaseDuration>\(lease)</NewLeaseDuration>")
        }
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: reply()) != .unreadable)
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: reply("0")) == .unreadable)
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: reply("65536")) == .unreadable)
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: reply("80", "ICMP")) == .unreadable)
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: reply("80", "TCP", "printer.local")) == .unreadable)
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: reply("80", "TCP", "192.168.1.5", "-1")) == .unreadable)
        #expect(UPnPPortMappingSOAP.parse(status: 500, body: Data("<html>error</html>".utf8)) == .unreadable)
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: Data("<broken".utf8)) == .unreadable)
        #expect(UPnPPortMappingSOAP.parse(status: 403, body: reply()) == .unreadable)
        #expect(UPnPPortMappingSOAP.parse(status: 500, body: reply()) == .unreadable)
    }

    @Test("fields outside the response element do not count", arguments: [
        // The fields are not under an Envelope/Body at all.
        Data("<r>\(validFields)</r>".utf8),
        // A Header carries the fields; the response itself is empty.
        envelope(header: validFields, "<u:GetGenericPortMappingEntryResponse xmlns:u=\"\(ipConnection)\"/>"),
        // The response element has another name.
        envelope("<u:DeletePortMappingResponse xmlns:u=\"\(ipConnection)\">\(validFields)</u:DeletePortMappingResponse>"),
        // The fields sit directly under Body.
        envelope(validFields)
    ])
    func rejectsMisplacedFields(body: Data) {
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: body) == .unreadable)
    }

    @Test("a Header field cannot override a response field")
    func headerDoesNotOverride() {
        let body = Self.envelope(
            header: "<NewInternalClient>192.168.1.66</NewInternalClient>",
            "<u:GetGenericPortMappingEntryResponse xmlns:u=\"\(Self.ipConnection)\">\(Self.validFields)</u:GetGenericPortMappingEntryResponse>"
        )
        guard case let .entry(mapping) = UPnPPortMappingSOAP.parse(status: 200, body: body) else {
            Issue.record("expected an entry")
            return
        }
        #expect(mapping.internalClient == "192.168.1.5")
    }

    @Test("duplicate fields, nested fake fields and a second Body child are unreadable", arguments: [
        response(validFields + "<NewInternalClient>192.168.1.66</NewInternalClient>"),
        response("<NewExternalPort>80</NewExternalPort><NewProtocol>TCP</NewProtocol><NewInternalPort>8080</NewInternalPort>"
            + "<NewInternalClient><NewInternalClient>192.168.1.66</NewInternalClient></NewInternalClient>"),
        response("<x><NewExternalPort>80</NewExternalPort></x>" + validFields),
        envelope("<u:GetGenericPortMappingEntryResponse xmlns:u=\"\(ipConnection)\">\(validFields)</u:GetGenericPortMappingEntryResponse>"
            + "<s:Fault><detail><UPnPError><errorCode>713</errorCode></UPnPError></detail></s:Fault>")
    ])
    func rejectsAmbiguousResponses(body: Data) {
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: body) == .unreadable)
    }

    @Test("a fault counts only directly under Body, with its code at detail/UPnPError/errorCode")
    func faultStructure() {
        // A Fault inside the Header, beside a real entry, is not a fault.
        let headerFault = Self.envelope(
            header: "<s:Fault><detail><UPnPError><errorCode>713</errorCode></UPnPError></detail></s:Fault>",
            "<u:GetGenericPortMappingEntryResponse xmlns:u=\"\(Self.ipConnection)\">\(Self.validFields)</u:GetGenericPortMappingEntryResponse>"
        )
        #expect(UPnPPortMappingSOAP.parse(status: 200, body: headerFault) != .fault(code: 713))
        // An errorCode elsewhere in the fault is not its code.
        let strayCode = Self.envelope("<s:Fault><faultstring><errorCode>713</errorCode></faultstring></s:Fault>")
        #expect(UPnPPortMappingSOAP.parse(status: 500, body: strayCode) == .fault(code: nil))
        // Two codes are ambiguous.
        let twoCodes = Self.envelope(
            "<s:Fault><detail><UPnPError><errorCode>713</errorCode><errorCode>606</errorCode></UPnPError></detail></s:Fault>"
        )
        #expect(UPnPPortMappingSOAP.parse(status: 500, body: twoCodes) == .unreadable)
    }

    // MARK: - Reading loop

    // swiftlint:disable:next force_unwrapping
    private static let service = UPnPWANService(serviceType: ipConnection, controlURL: "http://192.168.1.1:44695/ctl/IPConn", subnetFilter: { _ in true })!

    /// A router with `count` entries that then sends `endFault`, recording the indexes asked.
    private static func router(
        entries count: Int,
        asked: Indexes,
        failAt: Int? = nil,
        endFault: Data = Data(endOfListFault.utf8)
    ) -> UPnPPortMappingReader.Call {
        { _, index in
            await asked.append(index)
            if index == failAt {
                return nil
            }
            if index < count {
                return (200, Data(Self.entry.utf8))
            }
            return (500, endFault)
        }
    }

    @Test("reads until the end-of-list fault and reports the list complete")
    func stopsOnFault() async {
        let asked = Indexes()
        let report = await UPnPPortMappingReader.readEntries(service: Self.service, call: Self.router(entries: 3, asked: asked))
        guard case let .mappings(mappings, isComplete) = report else {
            Issue.record("expected mappings")
            return
        }
        #expect(mappings.count == 3)
        #expect(isComplete)
        #expect(await asked.values == [0, 1, 2, 3])
    }

    @Test("a call with no reply stops the loop and marks the list incomplete")
    func stopsIncompleteOnNoReply() async {
        let asked = Indexes()
        let report = await UPnPPortMappingReader.readEntries(service: Self.service, call: Self.router(entries: 5, asked: asked, failAt: 2))
        guard case let .mappings(mappings, isComplete) = report else {
            Issue.record("expected mappings")
            return
        }
        #expect(mappings.count == 2)
        #expect(!isComplete)
        #expect(await asked.values == [0, 1, 2])
    }

    @Test("only end-of-list faults (713, 714) complete the list; other or missing codes leave it incomplete", arguments: [
        ("713", true), ("714", true), ("606", false), ("501", false), ("716", false), (nil, false)
    ] as [(String?, Bool)])
    func faultCodesDecideCompleteness(code: String?, complete: Bool) async {
        let asked = Indexes()
        let report = await UPnPPortMappingReader.readEntries(
            service: Self.service, call: Self.router(entries: 0, asked: asked, endFault: Self.fault(code: code))
        )
        #expect(report == .mappings([], isComplete: complete))
        #expect(await asked.values == [0])
    }

    @Test("the entry cap stops the loop and marks the list incomplete")
    func stopsAtCap() async {
        let asked = Indexes()
        let report = await UPnPPortMappingReader.readEntries(service: Self.service, call: Self.router(entries: 1000, asked: asked), maxEntries: 4)
        guard case let .mappings(mappings, isComplete) = report else {
            Issue.record("expected mappings")
            return
        }
        #expect(mappings.count == 4)
        #expect(!isComplete)
        #expect(await asked.values == [0, 1, 2, 3])
    }

    @Test("no responders is noGateway; responders without a WAN service is noWANService")
    func gatewayStates() async {
        let none = await UPnPPortMappingReader.read(subnetFilter: lan, search: { [:] }, fetch: { _ in nil }, call: { _, _ in nil })
        #expect(none == .noGateway)
        let hue = "<root><device><friendlyName>Hue</friendlyName></device></root>"
        let noWAN = await UPnPPortMappingReader.read(
            subnetFilter: lan,
            search: { ["192.168.1.84": ["http://192.168.1.84/description.xml"]] },
            fetch: { _ in Data(hue.utf8) },
            call: { _, _ in nil }
        )
        #expect(noWAN == .noWANService)
        let offLAN = await UPnPPortMappingReader.read(
            subnetFilter: lan, search: { ["10.0.0.1": ["http://10.0.0.1/d.xml"]] }, fetch: { _ in nil }, call: { _, _ in nil }
        )
        #expect(offLAN == .noGateway)
    }

    @Test("the whole read finds the router among responders and lists its forwards")
    func fullRead() async {
        let asked = Indexes()
        let report = await UPnPPortMappingReader.read(
            subnetFilter: lan,
            search: { [
                "192.168.1.84": ["http://192.168.1.84/description.xml"],
                "192.168.1.1": ["http://192.168.1.1:44695/rootDesc.xml"]
            ] },
            fetch: { url in url.host == "192.168.1.1" ? Data(Self.routerDescription.utf8) : Data("<root><device><friendlyName>Hue</friendlyName></device></root>".utf8) },
            call: Self.router(entries: 2, asked: asked)
        )
        guard case let .mappings(mappings, isComplete) = report else {
            Issue.record("expected mappings")
            return
        }
        #expect(mappings.count == 2)
        #expect(isComplete)
    }
}

private actor Indexes {
    private var list: [Int] = []
    func append(_ index: Int) { list.append(index) }
    var values: [Int] { list }
}
