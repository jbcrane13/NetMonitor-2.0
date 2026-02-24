import Foundation
import SwiftUI
import CoreLocation
import NetMonitorCore

/// A single hop enriched with geolocation data.
struct GeoTraceHop: Identifiable {
    let id: UUID
    let hop: TracerouteHop
    var location: GeoLocation?

    init(hop: TracerouteHop) {
        self.id = hop.id
        self.hop = hop
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let loc = location else { return nil }
        return CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
    }

    var latencyColor: Color {
        guard let avg = hop.averageTime else { return .gray }
        if avg < 50 { return .green }
        if avg < 150 { return .yellow }
        return .red
    }
}

/// Combines traceroute hops with IP geolocation to build a map-ready data model.
@MainActor
@Observable
final class GeoTraceViewModel {

    // MARK: - Input

    var host: String = ""

    // MARK: - State

    var isRunning: Bool = false
    var hops: [GeoTraceHop] = []
    var selectedHop: GeoTraceHop?
    var errorMessage: String?

    // MARK: - Dependencies

    private let tracerouteService: any TracerouteServiceProtocol
    private let geoLocationService: any GeoLocationServiceProtocol
    private var traceTask: Task<Void, Never>?

    init(
        tracerouteService: any TracerouteServiceProtocol = TracerouteService(),
        geoLocationService: any GeoLocationServiceProtocol = GeoLocationService()
    ) {
        self.tracerouteService = tracerouteService
        self.geoLocationService = geoLocationService
    }

    // MARK: - Computed

    var canTrace: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && !isRunning
    }

    var locatedHops: [GeoTraceHop] {
        hops.filter { $0.location != nil }
    }

    var mapCoordinates: [CLLocationCoordinate2D] {
        locatedHops.compactMap(\.coordinate)
    }

    // MARK: - Actions

    func startTrace() {
        guard canTrace else { return }
        clearResults()
        isRunning = true

        let trimmedHost = host.trimmingCharacters(in: .whitespaces)

        traceTask = Task {
            let stream = await tracerouteService.trace(host: trimmedHost, maxHops: 30, timeout: nil)

            for await hop in stream {
                guard !Task.isCancelled else { break }
                let geoHop = GeoTraceHop(hop: hop)
                hops.append(geoHop)

                if let ip = hop.ipAddress, !hop.isTimeout {
                    let hopId = geoHop.id
                    Task {
                        if let location = try? await geoLocationService.lookup(ip: ip) {
                            if let idx = hops.firstIndex(where: { $0.id == hopId }) {
                                hops[idx].location = location
                            }
                        }
                    }
                }
            }

            isRunning = false
            ToolActivityLog.shared.add(
                tool: "Geo Trace",
                target: trimmedHost,
                result: "\(hops.count) hops",
                success: !hops.isEmpty
            )
        }
    }

    func stopTrace() {
        traceTask?.cancel()
        traceTask = nil
        Task { await tracerouteService.stop() }
        isRunning = false
    }

    func selectHop(_ hop: GeoTraceHop) {
        selectedHop = (selectedHop?.id == hop.id) ? nil : hop
    }

    func clearResults() {
        hops.removeAll()
        selectedHop = nil
        errorMessage = nil
    }
}
