import Foundation
import Testing
@testable import NetworkScanKit

/// #386: Bonjour TXT records, models, and resolving without opening a connection.
@Suite("Bonjour TXT")
struct BonjourTXTTests {

    /// Builds DNS-SD TXT wire data from strings (each length-prefixed).
    private func wire(_ entries: [String]) -> [UInt8] {
        entries.flatMap { entry -> [UInt8] in
            let bytes = Array(entry.utf8)
            return [UInt8(bytes.count)] + bytes
        }
    }

    @Test("Parses a _device-info TXT record")
    func parsesDeviceInfo() {
        let txt = BonjourTXT.parse(wire(["model=MacBookPro18,1", "osxvers=24", "ecolor=157,157,160"]))
        #expect(txt == ["model": "MacBookPro18,1", "osxvers": "24", "ecolor": "157,157,160"])
    }

    @Test("Parses an AirPlay TXT record with mixed-case keys and flags")
    func parsesAirPlay() {
        let txt = BonjourTXT.parse(wire(["deviceid=AA:BB:CC:DD:EE:FF", "Model=AppleTV14,1", "flags=0x244", "acl"]))
        #expect(txt["model"] == "AppleTV14,1")
        #expect(txt["acl"]?.isEmpty == true)
        #expect(txt["deviceid"] == "AA:BB:CC:DD:EE:FF")
    }

    @Test("Parses a Cast TXT record")
    func parsesCast() {
        let txt = BonjourTXT.parse(wire(["id=4d6a2b", "md=Chromecast", "fn=Living Room TV", "ve=05"]))
        #expect(txt["md"] == "Chromecast")
        #expect(txt["fn"] == "Living Room TV")
    }

    @Test("Empty, zero-length and truncated records parse safely")
    func parsesMalformed() {
        #expect(BonjourTXT.parse([UInt8]()).isEmpty)
        #expect(BonjourTXT.parse([0]).isEmpty)
        #expect(BonjourTXT.parse([0, 3] + Array("a=1".utf8)) == ["a": "1"])
        // The second entry claims 9 bytes but only 2 follow.
        #expect(BonjourTXT.parse(wire(["a=1"]) + [9, 0x62, 0x3D]) == ["a": "1"])
        // "=x" has no key.
        #expect(BonjourTXT.parse(wire(["=x", "b=2"])) == ["b": "2"])
        // The first occurrence of a key wins.
        #expect(BonjourTXT.parse(wire(["model=A", "model=B"])) == ["model": "A"])
    }

    @Test("Model keys per service type", arguments: [
        ("_device-info._tcp", ["model": "MacBookPro18,1"], "MacBookPro18,1"),
        ("_device-info._tcp.", ["model": "Mac16,10"], "Mac16,10"),
        ("_airplay._tcp.", ["model": "AppleTV14,1"], "AppleTV14,1"),
        ("_AirPlay._tcp.local.", ["model": "AppleTV14,1"], "AppleTV14,1"),
        ("_raop._tcp.", ["am": "AudioAccessory5,1"], "AudioAccessory5,1"),
        ("_googlecast._tcp.", ["md": "Chromecast"], "Chromecast"),
        ("_googlecast._tcp.", ["model": "Chromecast"], nil),
        ("_http._tcp.", ["model": "Something"], nil),
        ("_airplay._tcp.", ["model": "  "], nil),
        ("_airplay._tcp.", [:], nil)
    ] as [(String, [String: String], String?)])
    func modelKeys(type: String, txt: [String: String], expected: String?) {
        #expect(BonjourTXT.model(serviceType: type, txt: txt) == expected)
    }

    @Test("Instance names are escaped for record queries")
    func escapesInstanceNames() {
        #expect(DNSSDResolver.escapedInstanceName("Blake’s MacBook Pro") == "Blake’s MacBook Pro")
        #expect(DNSSDResolver.escapedInstanceName("v1.2 box") == "v1\\.2 box")
        #expect(DNSSDResolver.escapedInstanceName("a\\b") == "a\\\\b")
    }
}

@Suite("DiscoveredDevice model")
struct DiscoveredDeviceModelTests {

    @Test("Older JSON without a model decodes as nil, and model round-trips")
    func decodesModel() throws {
        let old = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","ipAddress":"192.0.2.5","discoveredAt":0,"source":"bonjour"}"#
        let decoded = try JSONDecoder().decode(DiscoveredDevice.self, from: Data(old.utf8))
        #expect(decoded.modelName == nil)

        let device = DiscoveredDevice(
            ipAddress: "192.0.2.6", hostname: "Mac", vendor: nil, macAddress: nil, latency: nil,
            discoveredAt: Date(timeIntervalSince1970: 0), source: .bonjour, modelName: "MacBookPro18,1"
        )
        let roundTrip = try JSONDecoder().decode(DiscoveredDevice.self, from: JSONEncoder().encode(device))
        #expect(roundTrip.modelName == "MacBookPro18,1")
        #expect(device.withCached(true).modelName == "MacBookPro18,1")
        #expect(device.withModelName("X").modelName == "X")
    }

    @Test("A Bonjour model wins over an SSDP modelName, in either order")
    func bonjourModelWinsOverSSDP() async {
        func device(_ source: DeviceSource, _ model: String?) -> DiscoveredDevice {
            DiscoveredDevice(
                ipAddress: "192.0.2.8", hostname: nil, vendor: nil, macAddress: nil,
                latency: nil, discoveredAt: Date(), source: source, modelName: model
            )
        }
        let ssdpFirst = ScanAccumulator()
        await ssdpFirst.upsert(device(.ssdp, "Apple TV"))
        await ssdpFirst.upsert(device(.bonjour, "AppleTV14,1"))
        #expect(await ssdpFirst.snapshot().first?.modelName == "AppleTV14,1")

        let bonjourFirst = ScanAccumulator()
        await bonjourFirst.upsert(device(.bonjour, "AppleTV14,1"))
        await bonjourFirst.upsert(device(.ssdp, "Apple TV"))
        #expect(await bonjourFirst.snapshot().first?.modelName == "AppleTV14,1")

        // SSDP still fills a model nothing else supplied, and Bonjour without a model keeps it.
        let ssdpOnly = ScanAccumulator()
        await ssdpOnly.upsert(device(.local, nil))
        await ssdpOnly.upsert(device(.ssdp, "Q80"))
        await ssdpOnly.upsert(device(.bonjour, nil))
        #expect(await ssdpOnly.snapshot().first?.modelName == "Q80")
    }

    @Test("The accumulator keeps a model through merges and latency updates")
    func accumulatorKeepsModel() async {
        let accumulator = ScanAccumulator()
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.0.2.7", hostname: nil, vendor: nil, macAddress: "00:11:22:33:44:55",
            latency: nil, discoveredAt: Date(), source: .local
        ))
        await accumulator.upsert(DiscoveredDevice(
            ipAddress: "192.0.2.7", hostname: "Living Room", vendor: nil, macAddress: nil,
            latency: nil, discoveredAt: Date(), source: .bonjour, modelName: "AppleTV14,1"
        ))
        await accumulator.setLatency(ip: "192.0.2.7", value: 3, source: .icmp)
        let device = await accumulator.snapshot().first
        #expect(device?.modelName == "AppleTV14,1")
        #expect(device?.hostname == "Living Room")
    }
}

@Suite("BonjourScanPhase models and resolution")
struct BonjourScanPhaseModelTests {

    private let context = ScanContext(hosts: [], subnetFilter: { $0.hasPrefix("192.0.2.") }, localIP: nil, requiredInterfaceType: .wifi)

    private func makePhase(
        services: [BonjourServiceInfo],
        resolutions: [String: BonjourResolution],
        deviceInfo: [String: String] = [:],
        calls: CallLog
    ) -> BonjourScanPhase {
        BonjourScanPhase(
            serviceProvider: { services },
            stopProvider: nil,
            resolver: { service in
                await calls.resolved(service.name + "|" + service.type)
                return resolutions[service.name + "|" + service.type]
            },
            addressResolver: { host in
                await calls.lookedUp(host)
                return host.hasPrefix("mac") ? ["192.0.2.10"] : []
            },
            deviceInfoQuery: { name in
                await calls.queried(name)
                return deviceInfo[name]
            }
        )
    }

    @Test("Models come from the service's own TXT record")
    func modelFromOwnTXT() async {
        let services = [
            BonjourServiceInfo(name: "Living Room", type: "_airplay._tcp.", domain: "local.", txtRecord: ["model": "AppleTV14,1"]),
            BonjourServiceInfo(name: "Chromecast-abc", type: "_googlecast._tcp.", domain: "local.", txtRecord: ["md": "Chromecast"])
        ]
        let calls = CallLog()
        let phase = makePhase(services: services, resolutions: [
            "Living Room|_airplay._tcp.": BonjourResolution(hostTarget: "192.0.2.20", port: 7000),
            "Chromecast-abc|_googlecast._tcp.": BonjourResolution(hostTarget: "192.0.2.21", port: 8009)
        ], calls: calls)
        let accumulator = ScanAccumulator()
        await phase.execute(context: context, accumulator: accumulator) { _ in }

        let byIP = await Dictionary(uniqueKeysWithValues: accumulator.snapshot().map { ($0.ipAddress, $0) })
        #expect(byIP["192.0.2.20"]?.modelName == "AppleTV14,1")
        #expect(byIP["192.0.2.21"]?.modelName == "Chromecast")
        #expect(await calls.queries.isEmpty, "No _device-info query when a model is already known")
    }

    @Test("A browsed _device-info model reaches the device by name and is never resolved")
    func deviceInfoByName() async {
        let services = [
            BonjourServiceInfo(name: "Blake’s MacBook Pro", type: "_device-info._tcp.", domain: "local.", txtRecord: ["model": "MacBookPro18,1"]),
            BonjourServiceInfo(name: "Blake’s MacBook Pro", type: "_ssh._tcp.", domain: "local.")
        ]
        let calls = CallLog()
        let phase = makePhase(services: services, resolutions: [
            "Blake’s MacBook Pro|_ssh._tcp.": BonjourResolution(hostTarget: "macbook.local.", port: 22)
        ], calls: calls)
        let accumulator = ScanAccumulator()
        await phase.execute(context: context, accumulator: accumulator) { _ in }

        let devices = await accumulator.snapshot()
        #expect(devices.count == 1)
        #expect(devices.first?.ipAddress == "192.0.2.10")
        #expect(devices.first?.modelName == "MacBookPro18,1")
        #expect(await calls.resolves == ["Blake’s MacBook Pro|_ssh._tcp."])
        #expect(await calls.lookups == ["macbook.local."])
    }

    @Test("Devices without a model ask for _device-info once per name")
    func deviceInfoQueryFallback() async {
        let services = [
            BonjourServiceInfo(name: "Studio", type: "_ssh._tcp.", domain: "local."),
            BonjourServiceInfo(name: "Studio", type: "_smb._tcp.", domain: "local."),
            BonjourServiceInfo(name: "Printer", type: "_ipp._tcp.", domain: "local.")
        ]
        let calls = CallLog()
        let phase = makePhase(services: services, resolutions: [
            "Studio|_ssh._tcp.": BonjourResolution(hostTarget: "192.0.2.30", port: 22),
            "Studio|_smb._tcp.": BonjourResolution(hostTarget: "192.0.2.30", port: 445),
            "Printer|_ipp._tcp.": BonjourResolution(hostTarget: "192.0.2.31", port: 631)
        ], deviceInfo: ["Studio": "Mac16,10"], calls: calls)
        let accumulator = ScanAccumulator()
        await phase.execute(context: context, accumulator: accumulator) { _ in }

        let byIP = await Dictionary(uniqueKeysWithValues: accumulator.snapshot().map { ($0.ipAddress, $0) })
        #expect(byIP["192.0.2.30"]?.modelName == "Mac16,10")
        #expect(byIP["192.0.2.31"]?.modelName == nil)
        #expect(await calls.queries.sorted() == ["Printer", "Studio"])
    }

    @Test("Services on the same host look its address up once")
    func hostLookupIsShared() async {
        let services = ["_ssh._tcp.", "_smb._tcp.", "_companion-link._tcp."].map {
            BonjourServiceInfo(name: "Studio", type: $0, domain: "local.")
        }
        let calls = CallLog()
        var resolutions: [String: BonjourResolution] = [:]
        for service in services {
            resolutions["Studio|" + service.type] = BonjourResolution(hostTarget: "mac-studio.local.", port: 22)
        }
        let phase = makePhase(services: services, resolutions: resolutions, calls: calls)
        let accumulator = ScanAccumulator()
        await phase.execute(context: context, accumulator: accumulator) { _ in }
        #expect(await accumulator.count == 1)
        #expect(await calls.resolves.count == 3)
        #expect(await calls.lookups == ["mac-studio.local."])
    }

    @Test("Unresolved and out-of-subnet services add nothing")
    func unresolvedServices() async {
        let services = [
            BonjourServiceInfo(name: "Gone", type: "_http._tcp.", domain: "local."),
            BonjourServiceInfo(name: "Elsewhere", type: "_http._tcp.", domain: "local.")
        ]
        let calls = CallLog()
        let phase = makePhase(services: services, resolutions: [
            "Elsewhere|_http._tcp.": BonjourResolution(hostTarget: "10.9.9.9", port: 80)
        ], calls: calls)
        let accumulator = ScanAccumulator()
        await phase.execute(context: context, accumulator: accumulator) { _ in }
        #expect(await accumulator.isEmpty)
        #expect(await calls.resolves.count == 2)
    }

    /// The pre-#386 phase opened one TCP connection per service through the shared
    /// `ConnectionBudget`. The resolver path holds no budget slot at any point.
    @Test("Resolving holds no connection slot")
    func resolvingHoldsNoConnectionSlot() async {
        let budget = ConnectionBudget.shared
        let services = (0..<20).map { BonjourServiceInfo(name: "Device \($0)", type: "_http._tcp.", domain: "local.") }
        let peak = PeakCounter()
        let phase = BonjourScanPhase(
            serviceProvider: { services },
            stopProvider: nil,
            resolver: { service in
                await peak.record(budget.activeCount)
                return BonjourResolution(hostTarget: "192.0.2.\(service.name.split(separator: " ")[1])", port: 80)
            },
            addressResolver: { _ in [] },
            deviceInfoQuery: { _ in
                await peak.record(budget.activeCount)
                return nil
            }
        )
        let accumulator = ScanAccumulator()
        await phase.execute(context: context, accumulator: accumulator) { _ in }
        #expect(await accumulator.count == 20)
        #expect(await peak.maximum == 0)
    }
}

private actor CallLog {
    private(set) var resolves: [String] = []
    private(set) var lookups: [String] = []
    private(set) var queries: [String] = []
    func resolved(_ key: String) { resolves.append(key) }
    func lookedUp(_ host: String) { lookups.append(host) }
    func queried(_ name: String) { queries.append(name) }
}

private actor PeakCounter {
    private(set) var maximum = 0
    func record(_ value: Int) { maximum = max(maximum, value) }
}
