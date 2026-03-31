import SwiftUI
import NetMonitorCore

/// DNS Lookup tool view for querying DNS records
struct DNSLookupToolView: View {
    let initialDomain: String?
    @State private var viewModel: DNSLookupToolViewModel

    init(initialDomain: String? = nil) {
        self.initialDomain = initialDomain
        self._viewModel = State(initialValue: DNSLookupToolViewModel(initialDomain: initialDomain))
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
        .navigationTitle("DNS Lookup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_dnsLookupTool")
    }

    // MARK: - Input Section

    private var inputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Domain")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ToolInputField(
                text: $viewModel.domain,
                placeholder: "Enter domain name",
                icon: "globe",
                keyboardType: .URL,
                accessibilityID: "dnsLookup_input_domain",
                onSubmit: {
                    if viewModel.canStartLookup {
                        Task { await viewModel.lookup() }
                    }
                }
            )

            // Record type picker
            HStack {
                Text("Record Type")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)

                Spacer()

                Picker("Type", selection: $viewModel.recordType) {
                    ForEach(viewModel.recordTypes, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.menu)
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("dnsLookup_picker_type")
            }
            .padding(.horizontal, 4)
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
            .accessibilityIdentifier("dnsLookup_button_run")

            if viewModel.result != nil {
                ToolClearButton(accessibilityID: "dnsLookup_button_clear") {
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
            .accessibilityIdentifier("dnsLookup_label_error")
        }

        if let result = viewModel.result {
            VStack(alignment: .leading, spacing: 12) {
                // Query info
                GlassCard {
                    VStack(spacing: 8) {
                        ToolResultRow(
                            label: "Domain",
                            value: result.domain,
                            icon: "globe",
                            isMonospaced: true,
                            selectable: true
                        )
                        Divider().background(Theme.Colors.glassBorder)
                        ToolResultRow(
                            label: "Server",
                            value: result.server,
                            icon: "server.rack",
                            selectable: true
                        )
                        Divider().background(Theme.Colors.glassBorder)
                        ToolResultRow(
                            label: "Query Time",
                            value: result.queryTimeText,
                            icon: "clock",
                            selectable: true
                        )
                    }
                }
                .accessibilityIdentifier("dnsLookup_section_queryInfo")

                // Records
                if !result.records.isEmpty {
                    HStack {
                        Text("Records")
                            .font(.headline)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        Spacer()

                        Text("\(result.records.count) found")
                            .font(.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }

                    GlassCard {
                        VStack(spacing: 0) {
                            ForEach(Array(result.records.enumerated()), id: \.element.id) { index, record in
                                DNSRecordRow(record: record)

                                if index < result.records.count - 1 {
                                    Divider()
                                        .background(Theme.Colors.glassBorder)
                                        .padding(.vertical, 8)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier("dnsLookup_section_records")
                }
            }
        }
    }
}

// MARK: - DNS Record Row

private struct DNSRecordRow: View {
    let record: DNSRecord

    var body: some View {
        HStack(spacing: 12) {
            // Record type badge
            Text(record.type.displayName)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: Theme.Layout.resultColumnMedium)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Theme.Colors.accent.opacity(0.2))
                )

            // Value
            VStack(alignment: .leading, spacing: 2) {
                Text(record.value)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .textSelection(.enabled)

                Text("TTL: \(record.ttlText)")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            Spacer()
        }
        .accessibilityIdentifier("dnsLookup_row_\(record.type.displayName)")
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        DNSLookupToolView()
    }
}
