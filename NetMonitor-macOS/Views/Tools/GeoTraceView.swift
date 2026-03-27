import SwiftUI
import MapKit
import CoreLocation
import NetMonitorCore

/// macOS GeoTrace — visual traceroute on a world map.
struct GeoTraceView: View {
    @State private var host = ""
    @State private var isRunning = false
    @State private var hops: [GeoTraceHop] = []
    @State private var selectedHop: GeoTraceHop?
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var traceTask: Task<Void, Never>?

    @State private var tracerouteService = TracerouteService()
    @State private var geoService = GeoLocationService()

    var body: some View {
        ToolSheetContainer(
            title: "Geo Trace",
            iconName: "map",
            closeAccessibilityID: "geoTrace_button_close",
            inputArea: { inputArea },
            outputArea: { mapArea },
            footerContent: { footer }
        )
        .onDisappear {
            traceTask?.cancel()
            traceTask = nil
        }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        HStack(spacing: 12) {
            TextField("Hostname or IP address", text: $host)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runTrace() }
                .disabled(isRunning)
                .accessibilityIdentifier("geoTrace_input_host")

            Button(isRunning ? "Stop" : "Trace") {
                if isRunning { stopTrace() } else { runTrace() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(host.isEmpty && !isRunning)
            .accessibilityIdentifier("geoTrace_button_trace")
        }
        .padding()
    }

    // MARK: - Map Area

    private var mapArea: some View {
        ZStack {
            Map(position: $cameraPosition) {
                ForEach(hops) { hop in
                    if let coord = hop.coordinate {
                        Annotation("", coordinate: coord, anchor: .center) {
                            macHopAnnotation(hop)
                                .onTapGesture {
                                    selectedHop = (selectedHop?.id == hop.id) ? nil : hop
                                }
                                .accessibilityIdentifier("geoTrace_hop_annotation_\(hop.hop.hopNumber)")
                        }
                        .annotationTitles(.hidden)
                    }
                }

                if locatedHops.count > 1 {
                    MapPolyline(coordinates: mapCoordinates)
                        .stroke(.blue.opacity(0.7), lineWidth: 2)
                }
            }
            .accessibilityIdentifier("geoTrace_map")

            if let hop = selectedHop {
                hopPopup(hop)
            }

            if hops.isEmpty && !isRunning {
                Text("Enter a hostname to trace its route on the map")
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func macHopAnnotation(_ hop: GeoTraceHop) -> some View {
        ZStack {
            Circle()
                .fill(hop.latencyColor.opacity(0.3))
                .frame(width: selectedHop?.id == hop.id ? 28 : 20)
            Circle()
                .fill(hop.latencyColor)
                .frame(width: selectedHop?.id == hop.id ? 14 : 10)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
        }
        .animation(.easeInOut(duration: 0.15), value: selectedHop?.id == hop.id)
    }

    private func hopPopup(_ hop: GeoTraceHop) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Hop \(hop.hop.hopNumber)")
                    .font(.headline)
                Spacer()
                Button { selectedHop = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("geoTrace_popup_button_close")
            }
            if let ip = hop.hop.ipAddress {
                Text(ip)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            if let loc = hop.location {
                Text("\(loc.city), \(loc.country)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let avg = hop.hop.averageTime {
                Text(String(format: "%.1f ms", avg))
                    .font(.caption)
                    .foregroundStyle(hop.latencyColor)
            }
        }
        .padding(12)
        .frame(width: 220)
        .macGlassCard(cornerRadius: 10, padding: 0, showBorder: true)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if isRunning {
                ProgressView().scaleEffect(0.7)
                Text("Tracing route to \(host)… \(hops.count) hops")
                    .foregroundStyle(.secondary)
            } else if !hops.isEmpty {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(MacTheme.Colors.success)
                Text("\(locatedHops.count)/\(hops.count) hops located").foregroundStyle(.secondary)
            } else {
                Text("Trace the geographic path to any host").foregroundStyle(.secondary)
            }

            Spacer()

            if !hops.isEmpty && !isRunning {
                Button("Clear") {
                    hops.removeAll()
                    selectedHop = nil
                    cameraPosition = .automatic
                }
                .accessibilityIdentifier("geoTrace_button_clear")
            }
        }
        .padding()
    }

    // MARK: - Computed

    private var locatedHops: [GeoTraceHop] { hops.filter { $0.location != nil } }
    private var mapCoordinates: [CLLocationCoordinate2D] { locatedHops.compactMap(\.coordinate) }

    // MARK: - Actions

    private func runTrace() {
        guard !host.isEmpty else { return }
        isRunning = true
        hops.removeAll()
        selectedHop = nil

        let trimmed = host.trimmingCharacters(in: .whitespacesAndNewlines)
        traceTask = Task {
            let stream = await tracerouteService.trace(host: trimmed, maxHops: 30)
            for await hop in stream {
                guard !Task.isCancelled else { break }
                let geoHop = GeoTraceHop(hop: hop)
                hops.append(geoHop)

                if let ip = hop.ipAddress, !hop.isTimeout {
                    let hopId = geoHop.id
                    Task {
                        if let location = try? await geoService.lookup(ip: ip) {
                            if let idx = hops.firstIndex(where: { $0.id == hopId }) {
                                hops[idx].location = location
                            }
                            fitMapToHops()
                        }
                    }
                }
            }
            isRunning = false
        }
    }

    private func stopTrace() {
        traceTask?.cancel()
        traceTask = nil
        Task { await tracerouteService.stop() }
        isRunning = false
    }

    private func fitMapToHops() {
        let coords = mapCoordinates
        guard coords.count > 1 else { return }
        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: (maxLat - minLat) * 1.4 + 2, longitudeDelta: (maxLon - minLon) * 1.4 + 2)
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - GeoTraceHop (macOS local copy)

private struct GeoTraceHop: Identifiable {
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
        return MacTheme.Colors.latencyColor(ms: avg)
    }
}

#Preview { GeoTraceView() }
