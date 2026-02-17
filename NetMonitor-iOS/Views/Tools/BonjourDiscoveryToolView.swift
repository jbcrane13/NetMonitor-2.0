import SwiftUI
import NetMonitorCore

/// Bonjour Discovery tool view for finding network services
struct BonjourDiscoveryToolView: View {
    @State private var viewModel = BonjourDiscoveryToolViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                controlSection
                servicesSection
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("Bonjour Discovery")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .onDisappear {
            viewModel.stopDiscovery()
        }
        .accessibilityIdentifier("screen_bonjourTool")
    }

    // MARK: - Control Section

    private var controlSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Services")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            Text("Discover services advertised on your local network using Bonjour/mDNS")
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            HStack(spacing: 12) {
                ToolRunButton(
                    title: "Start Discovery",
                    icon: "antenna.radiowaves.left.and.right",
                    isRunning: viewModel.isDiscovering,
                    stopTitle: "Stop Discovery",
                    action: {
                        if viewModel.isDiscovering {
                            viewModel.stopDiscovery()
                        } else {
                            viewModel.startDiscovery()
                        }
                    }
                )
                .accessibilityIdentifier("bonjour_button_run")

                if !viewModel.services.isEmpty && !viewModel.isDiscovering {
                    ToolClearButton(accessibilityID: "bonjour_button_clear") {
                        viewModel.clearResults()
                    }
                }
            }
        }
    }

    // MARK: - Services Section

    @ViewBuilder
    private var servicesSection: some View {
        if viewModel.services.isEmpty && viewModel.isDiscovering {
            GlassCard {
                HStack {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))

                    Text("Discovering services...")
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)

                    Spacer()
                }
            }
        } else if viewModel.services.isEmpty && viewModel.hasDiscoveredOnce && !viewModel.isDiscovering {
            EmptyStateView(
                icon: "antenna.radiowaves.left.and.right.slash",
                title: "No Services Found",
                description: "No Bonjour/mDNS services were discovered on your local network. Try scanning again or check that devices are advertising services."
            )
            .accessibilityIdentifier("bonjour_emptystate_noservices")
        } else if !viewModel.services.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Discovered Services")
                        .font(.headline)
                        .foregroundStyle(Theme.Colors.textPrimary)

                    Spacer()

                    Text("\(viewModel.services.count) found")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                ForEach(viewModel.sortedCategories, id: \.self) { category in
                    if let categoryServices = viewModel.groupedServices[category] {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundStyle(Theme.Colors.accent)

                            GlassCard {
                                VStack(spacing: 0) {
                                    ForEach(Array(categoryServices.enumerated()), id: \.element.id) { index, service in
                                        BonjourServiceRow(service: service)

                                        if index < categoryServices.count - 1 {
                                            Divider()
                                                .background(Theme.Colors.glassBorder)
                                                .padding(.vertical, 8)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("bonjour_section_services")
        }
    }
}

// MARK: - Bonjour Service Row

private struct BonjourServiceRow: View {
    let service: BonjourService

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: iconForService)
                    .font(.title3)
                    .foregroundStyle(Theme.Colors.accent)

                Text(service.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                if let port = service.port {
                    Text(":\(port)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }

            Text(service.type)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)

            if let host = service.hostName {
                Text(host)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
        .accessibilityIdentifier("bonjour_service_\(service.name)")
    }

    private var iconForService: String {
        switch service.serviceCategory {
        case "Web": return "globe"
        case "Remote Access": return "terminal"
        case "File Sharing": return "folder"
        case "Printing": return "printer"
        case "AirPlay": return "airplayaudio"
        case "Chromecast": return "tv"
        case "Spotify": return "music.note"
        case "HomeKit": return "homekit"
        default: return "network"
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        BonjourDiscoveryToolView()
    }
}
