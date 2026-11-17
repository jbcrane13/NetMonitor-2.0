import Testing
import Foundation
@testable import NetworkScanKit

/// Samples are real descriptions from a home LAN (Nov 2026) with addresses, serials and
/// UUIDs removed, plus a TV in the common Samsung DIAL layout.
@Suite("UPnPDeviceDescription")
struct UPnPDeviceDescriptionTests {

    // A UniFi gateway: the root device nests WANDevice and WANConnectionDevice,
    // each with its own friendlyName and manufacturer.
    static let router = #"""
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0" configId="1337"><specVersion><major>1</major><minor>1</minor></specVersion>\#
    <device><deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:2</deviceType><friendlyName>UniFi Dream Machine</friendlyName>\#
    <manufacturer>Ubiquiti Networks</manufacturer><manufacturerURL>http://ui.com</manufacturerURL>\#
    <modelDescription>UniFi Cloud Gateway Max</modelDescription><modelName>UCGMAX</modelName><modelNumber>00288d0f</modelNumber>\#
    <serialNumber>REDACTED</serialNumber><UDN>uuid:REDACTED</UDN><serviceList><service>\#
    <serviceType>urn:schemas-upnp-org:service:Layer3Forwarding:1</serviceType><SCPDURL>/L3F.xml</SCPDURL></service></serviceList>\#
    <deviceList><device><deviceType>urn:schemas-upnp-org:device:WANDevice:2</deviceType><friendlyName>WANDevice</friendlyName>\#
    <manufacturer>MiniUPnP</manufacturer><modelName>MiniUPnPd</modelName><UDN>uuid:REDACTED</UDN>\#
    <deviceList><device><deviceType>urn:schemas-upnp-org:device:WANConnectionDevice:2</deviceType>\#
    <friendlyName>WANConnectionDevice</friendlyName><manufacturer>MiniUPnP</manufacturer><modelName>MiniUPnPd</modelName>\#
    </device></deviceList></device></deviceList><presentationURL>http://x.x.x.x/</presentationURL></device></root>
    """#

    static let hueBridge = """
    <?xml version="1.0" encoding="UTF-8" ?>
    <root xmlns="urn:schemas-upnp-org:device-1-0">
    <specVersion>
    <major>1</major>
    <minor>0</minor>
    </specVersion>
    <URLBase>http://x.x.x.x:80/</URLBase>
    <device>
    <deviceType>urn:schemas-upnp-org:device:Basic:1</deviceType>
    <friendlyName>Hue Things</friendlyName>
    <manufacturer>Signify</manufacturer>
    <manufacturerURL>http://www.philips-hue.com</manufacturerURL>
    <modelDescription>Philips hue Personal Wireless Lighting</modelDescription>
    <modelName>Philips hue bridge 2015</modelName>
    <modelNumber>BSB002</modelNumber>
    <serialNumber>REDACTED</serialNumber>
    <UDN>uuid:REDACTED</UDN>
    <presentationURL>index.html</presentationURL>
    </device>
    </root>
    """

    static let tv = """
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0" xmlns:sec="http://www.sec.co.kr/dlna" xmlns:dlna="urn:schemas-dlna-org:device-1-0">
      <specVersion><major>1</major><minor>0</minor></specVersion>
      <device>
        <deviceType>urn:dial-multiscreen-org:device:dialreceiver:1</deviceType>
        <friendlyName>[TV] Samsung Q80 Series (65)</friendlyName>
        <manufacturer>Samsung Electronics</manufacturer>
        <manufacturerURL>http://www.samsung.com/sec</manufacturerURL>
        <modelDescription>Samsung TV NS</modelDescription>
        <modelName>QN65Q80BAFXZA</modelName>
        <modelNumber>1.0</modelNumber>
        <UDN>uuid:REDACTED</UDN>
        <sec:deviceID>REDACTED</sec:deviceID>
        <sec:ProductCap>Resolution:3840X2160,Tizen,Y2022</sec:ProductCap>
      </device>
    </root>
    """

    private func parse(_ xml: String) -> UPnPDeviceDescription? {
        UPnPDeviceDescription.parse(Data(xml.utf8))
    }

    @Test("router: the root device wins over nested WANDevice entries")
    func routerUsesRootDevice() {
        #expect(parse(Self.router) == UPnPDeviceDescription(
            friendlyName: "UniFi Dream Machine",
            manufacturer: "Ubiquiti Networks",
            modelName: "UCGMAX"
        ))
    }

    @Test("Hue bridge: fields parse and whitespace is trimmed")
    func hueBridge() {
        #expect(parse(Self.hueBridge) == UPnPDeviceDescription(
            friendlyName: "Hue Things",
            manufacturer: "Signify",
            modelName: "Philips hue bridge 2015"
        ))
    }

    @Test("TV: vendor-namespaced extra elements are ignored")
    func tv() {
        #expect(parse(Self.tv) == UPnPDeviceDescription(
            friendlyName: "[TV] Samsung Q80 Series (65)",
            manufacturer: "Samsung Electronics",
            modelName: "QN65Q80BAFXZA"
        ))
    }

    @Test("CDATA-only values parse")
    func cdataOnly() {
        let xml = "<root><device><friendlyName><![CDATA[Kitchen & Den]]></friendlyName><manufacturer><![CDATA[Sonos, Inc.]]></manufacturer></device></root>"
        #expect(parse(xml) == UPnPDeviceDescription(friendlyName: "Kitchen & Den", manufacturer: "Sonos, Inc.", modelName: nil))
    }

    @Test("values mixing text and CDATA parse in order")
    func cdataMixed() {
        let xml = "<root><device><friendlyName> Living <![CDATA[Room <TV>]]> 2 </friendlyName><modelName>Q<![CDATA[80]]></modelName></device></root>"
        #expect(parse(xml) == UPnPDeviceDescription(friendlyName: "Living Room <TV> 2", manufacturer: nil, modelName: "Q80"))
    }

    @Test("a missing field is nil; the others still parse")
    func partialFields() {
        let xml = "<root><device><manufacturer>Sonos, Inc.</manufacturer></device></root>"
        #expect(parse(xml) == UPnPDeviceDescription(friendlyName: nil, manufacturer: "Sonos, Inc.", modelName: nil))
    }

    @Test("malformed XML returns nil")
    func malformed() {
        #expect(parse("<root><device><friendlyName>TV</friendlyName></device>") == nil)
        #expect(parse("not xml at all") == nil)
        #expect(UPnPDeviceDescription.parse(Data()) == nil)
    }

    @Test("a document with no root device fields returns nil")
    func noFields() {
        #expect(parse("<root><device><deviceType>x</deviceType></device></root>") == nil)
        #expect(parse("<other><device><friendlyName>TV</friendlyName></device></other>") == nil)
    }

    @Test("input over 64 KB returns nil")
    func oversized() {
        let padding = String(repeating: "a", count: UPnPDeviceDescription.maxBytes)
        let xml = "<root><device><friendlyName>TV</friendlyName><x>\(padding)</x></device></root>"
        #expect(parse(xml) == nil)
    }

    @Test("an overlong field is cut to the field limit")
    func overlongField() {
        let name = String(repeating: "n", count: 500)
        let result = parse("<root><device><friendlyName>\(name)</friendlyName></device></root>")
        #expect(result?.friendlyName?.count == UPnPDeviceDescription.maxFieldLength)
    }
}
