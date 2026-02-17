//
//  SettingsView.swift
//  NetMonitor
//
//  Tab-based settings interface with 7 sections.
//

import SwiftUI

/// Settings tab options
enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case monitoring = "Monitoring"
    case notifications = "Notifications"
    case network = "Network"
    case data = "Data"
    case appearance = "Appearance"
    case companion = "Companion"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .general: return "gearshape"
        case .monitoring: return "waveform.path.ecg"
        case .notifications: return "bell"
        case .network: return "network"
        case .data: return "externaldrive"
        case .appearance: return "paintbrush"
        case .companion: return "iphone"
        }
    }
}

struct SettingsView: View {
    @State private var selectedTab: SettingsTab = .general

    var body: some View {
        HStack(spacing: 0) {
            // Settings sidebar
            List(SettingsTab.allCases, selection: $selectedTab) { tab in
                Label(tab.rawValue, systemImage: tab.iconName)
                    .tag(tab)
                    .accessibilityIdentifier("settings_tab_\(tab.rawValue.lowercased())")
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

            // Settings detail
            settingsContent(for: selectedTab)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Settings")
    }

    @ViewBuilder
    private func settingsContent(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView()
        case .monitoring:
            MonitoringSettingsView()
        case .notifications:
            NotificationSettingsView()
        case .network:
            NetworkSettingsView()
        case .data:
            DataSettingsView()
        case .appearance:
            AppearanceSettingsView()
        case .companion:
            CompanionSettingsView()
        }
    }
}

#Preview {
    SettingsView()
}
