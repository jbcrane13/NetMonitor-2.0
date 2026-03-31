import SwiftUI
import MapKit
import CoreLocation
import NetMonitorCore

/// Visual traceroute — plots each hop on a world map with a connecting polyline.
struct GeoTraceView: View {
    var initialHost: String?
    @State private var viewModel = GeoTraceViewModel()
    @State private var cameraPosition: MapCameraPosition = .automatic

    var body: some View {
        VStack(spacing: 0) {
            inputSection
            mapSection
            if let hop = viewModel.selectedHop {
                hopDetailPanel(hop)
            }
        }
        .themedBackground()
        .navigationTitle("Geo Trace")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_geoTrace")
        .onAppear {
            if let host = initialHost, viewModel.host.isEmpty {
                viewModel.host = host
            }
        }
        .onChange(of: viewModel.locatedHops.count) { _, _ in
            fitMapToHops()
        }
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                ToolInputField(
                    text: $viewModel.host,
                    placeholder: "Hostname or IP address",
                    icon: "map",
                    keyboardType: .URL,
                    accessibilityID: "geoTrace_input_host",
                    onSubmit: {
                        if viewModel.canTrace { viewModel.startTrace() }
                    }
                )

                Button {
                    if viewModel.isRunning {
                        viewModel.stopTrace()
                    } else {
                        viewModel.startTrace()
                    }
                } label: {
                    if viewModel.isRunning {
                        Label("Stop", systemImage: "stop.fill")
                            .foregroundStyle(Theme.Colors.error)
                    } else {
                        Label("Trace", systemImage: "play.fill")
                            .foregroundStyle(Theme.Colors.accent)
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: 12, padding: 0)
                .disabled(!viewModel.canTrace && !viewModel.isRunning)
                .accessibilityIdentifier("geoTrace_button_trace")
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if viewModel.isRunning {
                HStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                        .scaleEffect(0.8)
                    Text("Tracing… \(viewModel.hops.count) hops")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, 12)
    }

    // MARK: - Map Section

    private var mapSection: some View {
        Map(position: $cameraPosition) {
            ForEach(viewModel.hops) { hop in
                if let coord = hop.coordinate {
                    Annotation("", coordinate: coord, anchor: .center) {
                        HopAnnotationView(hop: hop, isSelected: viewModel.selectedHop?.id == hop.id)
                            .onTapGesture { viewModel.selectHop(hop) }
                            .accessibilityIdentifier("geoTrace_label_annotation\(hop.hop.hopNumber)")
                    }
                    .annotationTitles(.hidden)
                }
            }

            if viewModel.mapCoordinates.count > 1 {
                MapPolyline(coordinates: viewModel.mapCoordinates)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .teal],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        lineWidth: 2
                    )
            }
        }
        .accessibilityIdentifier("geoTrace_label_map")
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .center) {
            if viewModel.hops.isEmpty && !viewModel.isRunning {
                mapEmptyState
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !viewModel.hops.isEmpty && !viewModel.isRunning {
                clearButton
            }
        }
    }

    private var mapEmptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "map")
                .font(.largeTitle)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text("Enter a host to trace its route")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private var clearButton: some View {
        Button {
            viewModel.clearResults()
            cameraPosition = .automatic
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(16)
        }
        .accessibilityIdentifier("geoTrace_button_clear")
    }

    // MARK: - Hop Detail Panel

    private func hopDetailPanel(_ hop: GeoTraceHop) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Hop \(hop.hop.hopNumber)")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Button {
                    viewModel.selectHop(hop)
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .accessibilityIdentifier("geoTrace_button_deselectHop")
            }

            HStack(spacing: 16) {
                if let loc = hop.location {
                    Label("\(loc.city), \(loc.country)", systemImage: "location")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let ip = hop.hop.ipAddress {
                    Label(ip, systemImage: "network")
                        .font(.caption)
                        .fontDesign(.monospaced)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                if let avg = hop.hop.averageTime {
                    Label(String(format: "%.1f ms", avg), systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(hop.latencyColor)
                }
            }
        }
        .padding(.horizontal, Theme.Layout.screenPadding)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 0, padding: 0)
    }

    // MARK: - Camera Helpers

    private func fitMapToHops() {
        let coords = viewModel.mapCoordinates
        guard coords.count > 1 else {
            if let first = coords.first {
                cameraPosition = .region(MKCoordinateRegion(
                    center: first,
                    span: MKCoordinateSpan(latitudeDelta: 5, longitudeDelta: 5)
                ))
            }
            return
        }

        let minLat = coords.map(\.latitude).min()!
        let maxLat = coords.map(\.latitude).max()!
        let minLon = coords.map(\.longitude).min()!
        let maxLon = coords.map(\.longitude).max()!

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) * 1.4 + 2,
            longitudeDelta: (maxLon - minLon) * 1.4 + 2
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }
}

// MARK: - Hop Annotation View

private struct HopAnnotationView: View {
    let hop: GeoTraceHop
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(hop.latencyColor.opacity(0.25))
                .frame(width: isSelected ? 36 : 28)

            Circle()
                .fill(hop.latencyColor)
                .frame(width: isSelected ? 18 : 14)
                .overlay(
                    Circle().stroke(Theme.Colors.backgroundBase, lineWidth: 2)
                )

            if isSelected {
                Text("\(hop.hop.hopNumber)")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

#Preview {
    NavigationStack {
        GeoTraceView()
    }
}
