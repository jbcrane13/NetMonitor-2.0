import Testing
import Foundation
@testable import NetworkScanKit

@Suite("SSDPScanPhase descriptions (#387)")
struct SSDPDescriptionPhaseTests {

    private static let context = ScanContext(
        hosts: [],
        subnetFilter: { $0.hasPrefix("192.168.1.") },
        localIP: nil,
        requiredInterfaceType: nil
    )

    private static func xml(_ name: String, maker: String, model: String) -> Data {
        Data("<root><device><friendlyName>\(name)</friendlyName><manufacturer>\(maker)</manufacturer><modelName>\(model)</modelName></device></root>".utf8)
    }

    private func run(
        replies: [String: [String]],
        fetch: @escaping SSDPScanPhase.FetchDescription
    ) async -> [DiscoveredDevice] {
        let phase = SSDPScanPhase(discover: { _ in replies }, fetchDescription: fetch)
        let accumulator = ScanAccumulator()
        await phase.execute(context: Self.context, accumulator: accumulator) { _ in }
        return await accumulator.sortedSnapshot()
    }

    @Test("a description's name, maker and model land on the device")
    func descriptionFieldsLand() async {
        let devices = await run(replies: ["192.168.1.20": ["http://192.168.1.20:8001/dmr.xml"]]) { _, _ in
            Self.xml("Living Room TV", maker: "Samsung Electronics", model: "QN65Q80B")
        }

        let tv = devices.first
        #expect(devices.count == 1)
        #expect(tv?.source == .ssdp)
        #expect(tv?.friendlyName == "Living Room TV")
        #expect(tv?.manufacturer == "Samsung Electronics")
        #expect(tv?.modelName == "QN65Q80B")
        #expect(tv?.displayName == "Living Room TV")
        #expect(tv?.vendorOrManufacturer == "Samsung Electronics")
        #expect(tv?.isCached == false)
    }

    @Test("a failed fetch keeps the device, without description fields")
    func failedFetchKeepsDevice() async {
        let devices = await run(replies: ["192.168.1.20": ["http://192.168.1.20/desc.xml"]]) { _, _ in nil }

        #expect(devices.map(\.ipAddress) == ["192.168.1.20"])
        #expect(devices.first?.friendlyName == nil)
        #expect(devices.first?.displayName == "192.168.1.20")
    }

    @Test("only LAN http LOCATIONs are fetched, each once; a responder outside the subnet is dropped")
    func fetchesOnlyValidLocationsOnce() async {
        let fetched = FetchedURLs()
        let devices = await run(replies: [
            "192.168.1.20": ["http://192.168.1.20/a.xml", "http://192.168.1.20/a.xml"],
            "192.168.1.30": ["https://192.168.1.30/a.xml", "http://8.8.8.8/a.xml"],
            "10.0.0.5": ["http://10.0.0.5/a.xml"]
        ]) { url, _ in
            await fetched.append(url.absoluteString)
            return Self.xml("Speaker", maker: "Sonos, Inc.", model: "One")
        }

        #expect(await fetched.values == ["http://192.168.1.20/a.xml"])
        #expect(devices.map(\.ipAddress) == ["192.168.1.20", "192.168.1.30"])
        #expect(devices.last?.friendlyName == nil)
    }

    @Test("the next LOCATION is tried when the first one does not parse")
    func triesNextLocation() async {
        let devices = await run(replies: ["192.168.1.1": ["http://192.168.1.1/bad.xml", "http://192.168.1.1/good.xml"]]) { url, _ in
            url.path == "/good.xml" ? Self.xml("Router", maker: "Ubiquiti Networks", model: "UCGMAX") : Data("<html>".utf8)
        }
        #expect(devices.first?.friendlyName == "Router")
    }

    @Test("a hostname and an OUI vendor found elsewhere stay ahead of the description")
    func existingNamesWin() async {
        let phase = SSDPScanPhase(discover: { _ in ["192.168.1.20": ["http://192.168.1.20/d.xml"]] }) { _, _ in
            Self.xml("TV", maker: "Samsung Electronics", model: "Q80")
        }
        let accumulator = ScanAccumulator()
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.168.1.20", hostname: "tv.lan", vendor: "Samsung Electronics Co.,Ltd",
            macAddress: "AA:BB:CC:DD:EE:FF", latency: nil, discoveredAt: Date(), source: .local
        ))

        await phase.execute(context: Self.context, accumulator: accumulator) { _ in }
        await accumulator.setLatency(ip: "192.168.1.20", value: 4, source: .icmp)

        let device = await accumulator.snapshot().first
        #expect(device?.displayName == "tv.lan")
        #expect(device?.vendorOrManufacturer == "Samsung Electronics Co.,Ltd")
        // setLatency rebuilds the device; the description fields must survive it.
        #expect(device?.friendlyName == "TV")
        #expect(device?.modelName == "Q80")
    }

    @Test("extractLocation reads the LOCATION header case-insensitively")
    func extractLocation() {
        let reply = "HTTP/1.1 200 OK\r\nCACHE-CONTROL: max-age=120\r\nlocation:  http://192.168.1.1:44695/rootDesc.xml\r\nST: upnp:rootdevice\r\n\r\n"
        #expect(SSDPScanPhase.extractLocation(fromSSDPResponse: reply) == "http://192.168.1.1:44695/rootDesc.xml")
        #expect(SSDPScanPhase.extractLocation(fromSSDPResponse: "HTTP/1.1 200 OK\r\nST: x\r\n\r\n") == nil)
    }

    @Test("older JSON without description fields decodes them as nil")
    func decodesOlderJSON() throws {
        let json = """
        {"id":"\(UUID().uuidString)","ipAddress":"192.168.1.5","discoveredAt":0,"source":"ssdp"}
        """
        let device = try JSONDecoder().decode(DiscoveredDevice.self, from: Data(json.utf8))
        #expect(device.friendlyName == nil)
        #expect(device.manufacturer == nil)
        #expect(device.modelName == nil)
    }
}

private actor FetchedURLs {
    private var urls: [String] = []
    func append(_ url: String) { urls.append(url) }
    var values: [String] { urls }
}
