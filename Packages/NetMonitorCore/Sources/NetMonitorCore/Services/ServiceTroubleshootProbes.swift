import Foundation

/// The troubleshooter's checks over the app's existing services (#451). Cancelling the task that
/// awaits a ping or port scan ends that run through its stream; the speed test is stopped.
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
    private let speedTestFinished: @MainActor () -> Void

    /// - Parameters:
    ///   - gateway: the router's address (`NetworkUtilities.detectDefaultGateway()` by default).
    ///   - canRunSpeedTest: claims the connection for a speed test; false while another runs, so two
    ///     never overlap. The result is not saved to speed test history: it's a diagnostic sample.
    ///   - speedTestFinished: releases that claim, after the test ends however it ends.
    public init(
        pingService: any PingServiceProtocol = PingService(),
        portScanner: any PortScannerServiceProtocol = PortScannerService(),
        dnsService: any DNSLookupServiceProtocol = DNSLookupService(),
        wifiService: any WiFiInfoServiceProtocol,
        speedTest: any SpeedTestServiceProtocol = SpeedTestService(),
        gateway: @escaping @MainActor () async -> String? = { NetworkUtilities.detectDefaultGateway() },
        canRunSpeedTest: @escaping @MainActor () -> Bool = { true },
        speedTestFinished: @escaping @MainActor () -> Void = {}
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

    /// Cancelling the caller ends the stream, which ends this run alone: the service is shared
    /// (the Ping tool may be running), so nothing here calls `stop()`.
    public func ping(_ host: String, count: Int) async -> [Double] {
        var times: [Double] = []
        for await result in await pingService.ping(host: host, count: count, timeout: Self.timeout) where !result.isTimeout {
            times.append(result.time)
        }
        return times
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

    public func downloadSpeed() async -> SpeedTestOutcome {
        guard canRunSpeedTest() else { return .busy }
        // Released whatever happens, so the scheduler and the Speed Test tool can run again.
        defer { speedTestFinished() }
        let service = speedTest
        let data = await withTaskCancellationHandler {
            try? await service.startTest()
        } onCancel: {
            Task { @MainActor in service.stopTest() }
        }
        guard !Task.isCancelled, let data else { return .failed }
        return .measured(downloadMbps: data.downloadSpeed)
    }

    /// Like `ping`, cancelling ends this scan's stream and so its run; no shared `stop()`.
    public func openPorts(on host: String, among ports: [Int]) async -> [Int] {
        var open: [Int] = []
        for await result in await portScanner.scan(host: host, ports: ports, timeout: Self.timeout) where result.state == .open {
            open.append(result.port)
        }
        return open.sorted()
    }
}
