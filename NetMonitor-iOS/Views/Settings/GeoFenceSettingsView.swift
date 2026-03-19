import SwiftUI
import MapKit
import CoreLocation

// MARK: - GeoFenceSettingsView

struct GeoFenceSettingsView: View {
    @State private var manager = GeoFenceManager.shared
    @State private var showingAddSheet = false

    var body: some View {
        List {
            // Permission banner
            if !manager.isAuthorized {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Location Permission Required", systemImage: "location.slash.fill")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundStyle(Theme.Colors.warning)
                        Text("GeoFence monitoring requires location access. Grant \"Always\" permission for background triggers.")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Button("Grant Permission") {
                            manager.requestAuthorization()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.Colors.accent)
                        .accessibilityIdentifier("geoFence_button_requestPermission")
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Permissions")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .listRowBackground(Theme.Colors.glassBackground)
            }

            // Geofences list
            Section {
                if manager.geofences.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "location.circle")
                            .font(.largeTitle)
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text("No GeoFences")
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        Text("Tap + to add a location trigger")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .accessibilityIdentifier("geoFence_empty_state")
                } else {
                    ForEach(manager.geofences) { fence in
                        GeoFenceRow(fence: fence, manager: manager)
                    }
                    .onDelete { offsets in
                        manager.removeGeofences(at: offsets)
                    }
                }
            } header: {
                Text("Configured GeoFences")
                    .foregroundStyle(Theme.Colors.textSecondary)
            } footer: {
                Text("GeoFences send a notification when you enter or exit the defined area. \"Always\" location permission enables background delivery.")
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .listRowBackground(Theme.Colors.glassBackground)

            // Last event
            if let event = manager.lastEvent {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: event.trigger == .enter
                              ? "arrow.down.circle.fill"
                              : "arrow.up.circle.fill")
                            .foregroundStyle(event.trigger == .enter
                                             ? Theme.Colors.success
                                             : Theme.Colors.warning)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.geofenceName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundStyle(Theme.Colors.textPrimary)
                            Text("\(event.trigger.displayName) · \(event.timestamp.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                } header: {
                    Text("Last Event")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .listRowBackground(Theme.Colors.glassBackground)
            }
        }
        .scrollContentBackground(.hidden)
        .themedBackground()
        .navigationTitle("GeoFence")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("geoFence_button_add")
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            GeoFenceAddSheet(manager: manager)
        }
        .accessibilityIdentifier("screen_geoFence")
    }
}

// MARK: - Row

private struct GeoFenceRow: View {
    let fence: GeoFenceEntry
    let manager: GeoFenceManager

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "location.circle.fill")
                .font(.title3)
                .foregroundStyle(fence.isEnabled ? Theme.Colors.accent : Theme.Colors.textTertiary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(fence.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                HStack(spacing: 4) {
                    Text(String(format: "%.0fm radius", fence.radius))
                    Text("·")
                    Text(fence.triggerOn.displayName)
                }
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { fence.isEnabled },
                set: { _ in manager.toggleEnabled(fence) }
            ))
            .tint(Theme.Colors.accent)
            .labelsHidden()
            .accessibilityIdentifier("geoFence_toggle_\(fence.id.uuidString)")
        }
        .accessibilityIdentifier("geoFence_row_\(fence.id.uuidString)")
    }
}

// MARK: - Add Sheet

struct GeoFenceAddSheet: View {
    let manager: GeoFenceManager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var radius: Double = 200
    @State private var triggerOn: GeoFenceTrigger = .enter
    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3318, longitude: -122.0312),
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
    )

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && selectedCoordinate != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Map with center-pin
                ZStack {
                    Map(position: $cameraPosition)
                        .onMapCameraChange(frequency: .onEnd) { context in
                            selectedCoordinate = context.region.center
                        }
                        .onAppear {
                            // Initialise coordinate to map's starting center
                            if let r = cameraPosition.region {
                                selectedCoordinate = r.center
                            }
                        }

                    // Center crosshair pin
                    VStack(spacing: 0) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.title)
                            .foregroundStyle(Theme.Colors.accent)
                            .shadow(radius: 2)
                        Color.clear.frame(height: 4)
                    }
                }
                .frame(height: 240)

                // Form
                List {
                    Section {
                        TextField("Name (e.g. Home, Office)", text: $name)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .autocorrectionDisabled()
                            .accessibilityIdentifier("geofence_name_field")
                    } header: {
                        Text("GeoFence Name")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .listRowBackground(Theme.Colors.glassBackground)

                    Section {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Radius")
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                Text(String(format: "%.0f m", radius))
                                    .foregroundStyle(Theme.Colors.accent)
                                    .monospacedDigit()
                            }
                            Slider(value: $radius, in: 100...5000, step: 50)
                                .tint(Theme.Colors.accent)
                                .accessibilityIdentifier("geoFence_slider_radius")
                        }
                    } header: {
                        Text("Detection Radius")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .listRowBackground(Theme.Colors.glassBackground)

                    Section {
                        Picker("Trigger", selection: $triggerOn) {
                            ForEach(GeoFenceTrigger.allCases, id: \.self) { trigger in
                                Text(trigger.displayName).tag(trigger)
                            }
                        }
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .accessibilityIdentifier("geoFence_picker_trigger")
                    } header: {
                        Text("Trigger On")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .listRowBackground(Theme.Colors.glassBackground)

                    if let coord = selectedCoordinate {
                        Section {
                            HStack {
                                Text("Latitude")
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                Text(String(format: "%.5f", coord.latitude))
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .monospacedDigit()
                            }
                            .accessibilityIdentifier("geoFence_row_latitude")
                            HStack {
                                Text("Longitude")
                                    .foregroundStyle(Theme.Colors.textPrimary)
                                Spacer()
                                Text(String(format: "%.5f", coord.longitude))
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                    .monospacedDigit()
                            }
                            .accessibilityIdentifier("geoFence_row_longitude")
                        } header: {
                            Text("Selected Location")
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        .listRowBackground(Theme.Colors.glassBackground)
                    }
                }
                .scrollContentBackground(.hidden)
                .themedBackground()
            }
            .themedBackground()
            .navigationTitle("Add GeoFence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityIdentifier("geoFence_button_cancel")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(!canSave)
                        .foregroundStyle(canSave ? Theme.Colors.accent : Theme.Colors.textTertiary)
                        .accessibilityIdentifier("geoFence_button_save")
                }
            }
        }
    }

    private func save() {
        guard let coord = selectedCoordinate else { return }
        let entry = GeoFenceEntry(
            name: name.trimmingCharacters(in: .whitespaces),
            latitude: coord.latitude,
            longitude: coord.longitude,
            radius: radius,
            triggerOn: triggerOn
        )
        manager.addGeofence(entry)
        dismiss()
    }
}

#Preview {
    NavigationStack {
        GeoFenceSettingsView()
    }
}
