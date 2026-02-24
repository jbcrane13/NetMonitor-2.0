import Foundation
import Testing
@testable import NetMonitor_iOS
import NetMonitorCore

@Suite("GeoTraceViewModel")
@MainActor
struct GeoTraceViewModelTests {

    @Test func initialState() {
        let vm = GeoTraceViewModel(
            tracerouteService: MockTracerouteService(),
            geoLocationService: MockGeoLocationService()
        )
        #expect(vm.host == "")
        #expect(vm.isRunning == false)
        #expect(vm.hops.isEmpty)
        #expect(vm.selectedHop == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func canTraceRequiresNonEmptyHost() {
        let vm = GeoTraceViewModel(
            tracerouteService: MockTracerouteService(),
            geoLocationService: MockGeoLocationService()
        )
        #expect(vm.canTrace == false)
        vm.host = "  "
        #expect(vm.canTrace == false)
        vm.host = "8.8.8.8"
        #expect(vm.canTrace == true)
    }

    @Test func startTracePopulatesHops() async {
        let tracerouteService = MockTracerouteService()
        tracerouteService.mockHops = [
            TracerouteHop(hopNumber: 1, ipAddress: "192.168.1.1"),
            TracerouteHop(hopNumber: 2, ipAddress: "10.0.0.1"),
            TracerouteHop(hopNumber: 3, ipAddress: "8.8.8.8")
        ]

        let vm = GeoTraceViewModel(
            tracerouteService: tracerouteService,
            geoLocationService: MockGeoLocationService()
        )
        vm.host = "8.8.8.8"
        vm.startTrace()

        // Wait for async trace to complete
        try? await Task.sleep(nanoseconds: 100_000_000)

        #expect(vm.hops.count == 3)
        #expect(vm.isRunning == false)
    }

    @Test func clearResultsResetsState() {
        let vm = GeoTraceViewModel(
            tracerouteService: MockTracerouteService(),
            geoLocationService: MockGeoLocationService()
        )
        vm.errorMessage = "error"
        vm.clearResults()
        #expect(vm.hops.isEmpty)
        #expect(vm.selectedHop == nil)
        #expect(vm.errorMessage == nil)
    }

    @Test func selectHopTogglesSelection() {
        let vm = GeoTraceViewModel(
            tracerouteService: MockTracerouteService(),
            geoLocationService: MockGeoLocationService()
        )
        let hop = GeoTraceHop(hop: TracerouteHop(hopNumber: 1, ipAddress: "1.2.3.4"))
        vm.selectHop(hop)
        #expect(vm.selectedHop?.id == hop.id)
        vm.selectHop(hop)
        #expect(vm.selectedHop == nil)
    }

    @Test func locatedHopsFiltersByLocation() async {
        let tracerouteService = MockTracerouteService()
        tracerouteService.mockHops = [
            TracerouteHop(hopNumber: 1, ipAddress: "192.168.1.1"),  // private, geo will fail
            TracerouteHop(hopNumber: 2, ipAddress: "8.8.8.8")       // public, geo will succeed
        ]

        let geoService = MockGeoLocationService()
        geoService.successIPs = ["8.8.8.8"]

        let vm = GeoTraceViewModel(
            tracerouteService: tracerouteService,
            geoLocationService: geoService
        )
        vm.host = "8.8.8.8"
        vm.startTrace()

        try? await Task.sleep(nanoseconds: 200_000_000)

        #expect(vm.hops.count == 2)
        #expect(vm.locatedHops.count == 1)
        #expect(vm.locatedHops.first?.hop.ipAddress == "8.8.8.8")
    }
}

// MARK: - Mock GeoLocation Service

private final class MockGeoLocationService: GeoLocationServiceProtocol, @unchecked Sendable {
    var successIPs: Set<String> = []
    var shouldFail = false

    func lookup(ip: String) async throws -> GeoLocation {
        if shouldFail || (!successIPs.isEmpty && !successIPs.contains(ip)) {
            throw GeoLocationError.lookupFailed("Mock failure")
        }
        return GeoLocation(
            ip: ip,
            country: "United States",
            countryCode: "US",
            region: "California",
            city: "Mountain View",
            latitude: 37.386,
            longitude: -122.0838,
            isp: "Google LLC"
        )
    }
}
