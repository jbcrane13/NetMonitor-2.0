import Foundation

/// The troubleshooter's checks over the app's existing services (#451). Cancelling the task that
/// awaits a check stops the service it runs on.
@MainActor
public final class ServiceTroubleshootProbes: TroubleshootProbing {
    /// How long each ping and port connect waits, in seconds.
    public static let timeout: TimeInterval = 2

    private let pingService: any PingServiceProtocol
    private let portScanner: any PortScannerServiceProtocol
    private let dnsService: any DNSLookupServiceProtocol
    private let wifiService: any WiFiInfoServiceProtocol
    private let speedTest: any SpeedTestServiceProtocol
    private let gateway: @MainActor () async -> String?
    private let canRunSpeedTest: @MainActor () -> Bool
    private let speedTestFinished: @MainActor (SpeedTestData?) -> Void

    /// - Parameters:
    ///   - gateway: the router's address (`NetworkUtilities.detectDefaultGateway()` by default).
    ///   - canRunSpeedTest: false while another speed test runs, so two never overlap.
    ///   - speedTestFinished: called after the troubleshooter's speed test, with its data or nil.
    public init(
        pingService: any PingServiceProtocol = PingService(),
        portScanner: any PortScannerServiceProtocol = PortScannerService(),
        dnsService: any DNSLookupServiceProtocol = DNSLookupService(),
        wifiService: any WiFiInfoServiceProtocol,
        speedTest: any SpeedTestServiceProtocol = SpeedTestService(),
        gateway: @escaping @MainActor () async -> String? = { NetworkUtilities.detectDefaultGateway() },
        canRunSpeedTest: @escaping @MainActor () -> Bool = { true },
        speedTestFinished: @escaping @MainActor (SpeedTestData?) -> Void = { _ in }
    ) {
        self.pingService = pingService
        self.portScanner = portScanner
        self.dnsService = dnsService
        self.wifiService = wifiService
        self.speedTest = speedTest
        self.gateway = gateway
        self.canRunSpeedTest = canRunSpeedTest
        self.speedTestFinished = speedTestFinished
    }

    public func gatewayAddress() async -> String? {
        await gateway()
    }

    public func ping(_ host: String, count: Int) async -> [Double] {
        let service = pingService
        return await withTaskCancellationHandler {
            var times: [Double] = []
            for await result in await service.ping(host: host, count: count, timeout: Self.timeout) where !result.isTimeout {
                times.append(result.time)
            }
            return times
        } onCancel: {
            Task { await service.stop() }
        }
    }

    /// The time of the first family that answers: IPv4, then IPv6 for a name with no A record.
    public func lookup(_ host: String) async -> Double? {
        for type in [DNSRecordType.a, .aaaa] {
            if let result = await dnsService.lookup(domain: host, recordType: type, server: nil), !result.records.isEmpty {
                return result.queryTime
            }
        }
        return nil
    }

    public func wifiReading() async -> WiFiReading? {
        // -100 and 0 are placeholders some readers report without a signal (#455).
        guard let wifi = await wifiService.fetchCurrentWiFi(), let rssi = wifi.signalDBm, rssi < 0, rssi > -100 else { return nil }
        return WiFiReading(rssi: rssi, noise: wifi.noiseLevel.flatMap { $0 < 0 ? $0 : nil })
    }

    public func downloadSpeed() async -> Double? {
        guard canRunSpeedTest() else { return nil }
        let service = speedTest
        let data = await withTaskCancellationHandler {
            try? await service.startTest()
        } onCancel: {
            Task { @MainActor in service.stopTest() }
        }
        let finished = Task.isCancelled ? nil : data
        speedTestFinished(finished)
        return finished?.downloadSpeed
    }

    public func openPorts(on host: String, among ports: [Int]) async -> [Int] {
        let scanner = portScanner
        return await withTaskCancellationHandler {
            var open: [Int] = []
            for await result in await scanner.scan(host: host, ports: ports, timeout: Self.timeout) where result.state == .open {
                open.append(result.port)
            }
            return open.sorted()
        } onCancel: {
            Task { await scanner.stop() }
        }
    }
}
