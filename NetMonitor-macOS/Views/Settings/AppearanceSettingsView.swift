//
//  AppearanceSettingsView.swift
//  NetMonitor
//
//  Visual appearance settings.
//

import SwiftUI

struct AppearanceSettingsView: View {
    @AppStorage("netmonitor.appearance.accentColor") private var accentColorHex = "#06B6D4"
    @AppStorage("netmonitor.appearance.compactMode") private var compactMode = false

    @State private var selectedColor: Color = .cyan

    private let presetColors: [(name: String, color: Color, hex: String)] = [
        ("Cyan", .cyan, "#06B6D4"),
        ("Blue", .blue, "#3B82F6"),
        ("Purple", .purple, "#8B5CF6"),
        ("Pink", .pink, "#EC4899"),
        ("Green", .green, "#22C55E"),
        ("Orange", .orange, "#F97316"),
    ]

    var body: some View {
        Form {
            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Accent Color")

                    HStack(spacing: 12) {
                        ForEach(presetColors, id: \.hex) { preset in
                            Button {
                                selectedColor = preset.color
                                accentColorHex = preset.hex
                            } label: {
                                Circle()
                                    .fill(preset.color)
                                    .frame(width: 32, height: 32)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(accentColorHex == preset.hex ? .white : .clear, lineWidth: 2)
                                    )
                                    .shadow(color: preset.color.opacity(0.5), radius: accentColorHex == preset.hex ? 4 : 0)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("appearance_button_color\(preset.name.lowercased())")
                        }
                    }
                }
            } header: {
                Text("Colors")
            } footer: {
                Text("Choose an accent color for the interface.")
            }

            SwiftUI.Section {
                Toggle("Compact mode", isOn: $compactMode)
                    .accessibilityIdentifier("settings_toggle_compactMode")
            } header: {
                Text("Layout")
            } footer: {
                Text("Compact mode reduces padding and uses smaller fonts for a denser display.")
            }
        }
        .formStyle(.grouped)
        .padding()
        .navigationTitle("Appearance")
        .onAppear {
            // Sync color from stored hex
            if let preset = presetColors.first(where: { $0.hex == accentColorHex }) {
                selectedColor = preset.color
            }
        }
    }
}

#Preview {
    AppearanceSettingsView()
}
