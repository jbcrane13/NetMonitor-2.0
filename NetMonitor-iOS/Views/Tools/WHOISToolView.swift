import SwiftUI
import NetMonitorCore

/// WHOIS tool view for domain information lookup
struct WHOISToolView: View {
    @State private var viewModel: WHOISToolViewModel

    init(initialDomain: String? = nil) {
        self._viewModel = State(initialValue: WHOISToolViewModel(initialDomain: initialDomain))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                inputSection
                controlSection
                resultsSection
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("WHOIS Lookup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_whoisTool")
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Domain")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ToolInputField(
                text: $viewModel.domain,
                placeholder: "Enter domain name (e.g., example.com)",
                icon: "doc.text.magnifyingglass",
                keyboardType: .URL,
                accessibilityID: "whois_input_domain",
                onSubmit: {
                    if viewModel.canStartLookup {
                        Task { await viewModel.lookup() }
                    }
                }
            )
        }
    }

    // MARK: - Control Section

    private var controlSection: some View {
        HStack(spacing: 12) {
            ToolRunButton(
                title: "Lookup",
                icon: "magnifyingglass",
                isRunning: viewModel.isLoading,
                stopTitle: "Looking up...",
                action: {
                    Task { await viewModel.lookup() }
                }
            )
            .disabled(!viewModel.canStartLookup)
            .accessibilityIdentifier("whois_button_run")

            if viewModel.result != nil {
                ToolClearButton(accessibilityID: "whois_button_clear") {
                    viewModel.clearResults()
                }
            }
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        if let error = viewModel.errorMessage {
            GlassCard {
                HStack {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(Theme.Colors.error)

                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.error)

                    Spacer()
                }
            }
            .accessibilityIdentifier("whois_label_error")
        }

        if let result = viewModel.result {
            VStack(alignment: .leading, spacing: 12) {
                // Domain info
                GlassCard {
                    VStack(spacing: 8) {
                        ToolResultRow(
                            label: "Domain",
                            value: result.query,
                            icon: "globe",
                            isMonospaced: true,
                            selectable: true
                        )

                        if let registrar = result.registrar {
                            Divider().background(Theme.Colors.glassBorder)
                            ToolResultRow(
                                label: "Registrar",
                                value: registrar,
                                icon: "building.2",
                                selectable: true
                            )
                        }
                    }
                }
                .accessibilityIdentifier("whois_section_domainInfo")

                // Dates
                if result.creationDate != nil || result.expirationDate != nil {
                    HStack {
                        Text("Domain Dates")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()
                    }

                    GlassCard {
                        VStack(spacing: 8) {
                            if let creation = result.creationDate {
                                ToolResultRow(
                                    label: "Created",
                                    value: creation.formatted(date: .abbreviated, time: .omitted),
                                    icon: "calendar.badge.plus",
                                    selectable: true
                                )
                            }

                            if let updated = result.updatedDate {
                                Divider().background(Theme.Colors.glassBorder)
                                ToolResultRow(
                                    label: "Updated",
                                    value: updated.formatted(date: .abbreviated, time: .omitted),
                                    icon: "calendar.badge.clock",
                                    selectable: true
                                )
                            }

                            if let expiration = result.expirationDate {
                                Divider().background(Theme.Colors.glassBorder)
                                ToolResultRow(
                                    label: "Expires",
                                    value: expiration.formatted(date: .abbreviated, time: .omitted),
                                    icon: "calendar.badge.exclamationmark",
                                    valueColor: expirationColor(result.daysUntilExpiration),
                                    selectable: true
                                )
                            }
                        }
                    }
                    .accessibilityIdentifier("whois_section_dates")
                }

                // Name servers
                if !result.nameServers.isEmpty {
                    HStack {
                        Text("Name Servers")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        Text("\(result.nameServers.count)")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    GlassCard {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(result.nameServers, id: \.self) { ns in
                                HStack {
                                    Image(systemName: "server.rack")
                                        .font(.caption)
                                        .foregroundStyle(Theme.Colors.textSecondary)

                                    Text(ns)
                                        .font(.system(.subheadline, design: .monospaced))
                                        .foregroundStyle(Theme.Colors.textPrimary)

                                    Spacer()
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("whois_section_nameServers")
                }
            }
        }
    }

    private func expirationColor(_ days: Int?) -> Color {
        guard let days = days else { return Theme.Colors.textPrimary }
        switch days {
        case ..<30: return Theme.Colors.error
        case 30..<90: return Theme.Colors.warning
        default: return Theme.Colors.success
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WHOISToolView()
    }
}
