import Testing
import Foundation
@testable import NetMonitor_iOS
import NetMonitorCore

/// What each tool hands the "Explain" card (#448).
@Suite(.serialized)
@MainActor
struct ToolInsightRequestTests {
    func until(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(2)) async {
        await waitUntil(condition, timeout: timeout)
    }

    @Test func portScannerExplainsTheFinishedScanOfTheHostItScanned() async {
        let service = MockPortScannerService()
        service.mockResults = [
            PortScanResult(port: 22, state: .closed),
            PortScanResult(port: 80, state: .open),
            PortScanResult(port: 443, state: .closed)
        ]
        let vm = PortScannerToolViewModel(portScannerService: service)
        #expect(vm.insightRequest == nil)

        vm.host = "192.168.1.20"
        vm.startScan()
        #expect(vm.insightRequest == nil)
        await until { !vm.isRunning }
        vm.host = "edited-after-the-scan"

        let request = vm.insightRequest
        #expect(request?.subject == "Port scan of 192.168.1.20")
        #expect(request?.facts == [
            "Number of ports scanned: 3",
            "Open ports (1): 80 (usually HTTP)",
            "Number of ports that did not accept a connection: 2",
            "The scan only checked whether each port accepts a connection; service names are the usual use of that port number."
        ])
    }

    @Test func speedTestHasNothingToExplainBeforeATestCompletes() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        #expect(vm.insightRequest == nil)
    }

    @Test func speedTestExplainsTheCompletedFigures() {
        let vm = SpeedTestToolViewModel(service: MockSpeedTestService())
        vm.downloadSpeed = 412
        vm.uploadSpeed = 21
        vm.latency = 18
        vm.jitter = 3
        vm.phase = .complete

        #expect(vm.insightRequest?.facts.prefix(4) == [
            "Download: 412 Mbps",
            "Upload: 21.0 Mbps",
            "Latency: 18.0 ms",
            "Jitter: 3.0 ms"
        ])

        vm.errorMessage = "Upload failed"
        #expect(vm.insightRequest == nil)
    }

    @Test func whoisExplainsTheResultOnScreen() {
        let vm = WHOISToolViewModel(whoisService: MockWHOISService())
        #expect(vm.insightRequest == nil)
        vm.result = WHOISResult(query: "example.org", registrar: "Namecheap", rawData: "")
        #expect(vm.insightRequest?.subject == "WHOIS lookup for example.org")
        vm.isLoading = true
        #expect(vm.insightRequest == nil)
    }

    @Test func dnsLookupExplainsTheResultOnScreen() {
        let vm = DNSLookupToolViewModel(dnsService: MockDNSLookupService())
        #expect(vm.insightRequest == nil)
        vm.result = DNSQueryResult(domain: "example.com", server: "1.1.1.1", queryType: .a, records: [], queryTime: 12)
        #expect(vm.insightRequest?.subject == "DNS lookup of A records for example.com")
    }

    @Test func tracerouteExplainsHopsOnlyOnceTheTraceStops() {
        let vm = TracerouteToolViewModel(tracerouteService: MockTracerouteService())
        vm.hops = [TracerouteHop(hopNumber: 1, ipAddress: "192.168.1.1", times: [2])]
        vm.isRunning = true
        #expect(vm.insightRequest == nil)
        vm.isRunning = false
        #expect(vm.insightRequest?.facts == ["Hop 1: 192.168.1.1, 2.0 ms"])
    }

    @Test func dnsLookupOfAllTypesKeepsItsScopeAfterTheToggleChanges() async {
        let service = MockDNSLookupService()
        service.mockAllResult = DNSQueryResult(
            domain: "example.com", server: "1.1.1.1", queryType: .a,
            records: [DNSRecord(name: "example.com", type: .mx, value: "mx1.example.com", ttl: 300, priority: 10)],
            queryTime: 12
        )
        let vm = DNSLookupToolViewModel(dnsService: service)
        vm.domain = "example.com"
        vm.queryAllTypes = true
        await vm.lookup()
        vm.queryAllTypes = false

        #expect(vm.insightRequest?.subject == "DNS lookup of all record types for example.com")
    }
}
