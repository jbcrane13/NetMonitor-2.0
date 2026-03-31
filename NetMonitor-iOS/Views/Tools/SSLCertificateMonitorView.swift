import SwiftUI
import NetMonitorCore

/// SSL Certificate & Domain Expiration Monitor with query and watch-list modes.
struct SSLCertificateMonitorView: View {
    @State private var viewModel = SSLCertificateMonitorViewModel()
    @State private var selectedTab = 0

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Layout.sectionSpacing) {
                modePicker
                if selectedTab == 0 {
                    querySection
                } else {
                    watchListSection
                }
            }
            .padding(.horizontal, Theme.Layout.screenPadding)
            .padding(.bottom, Theme.Layout.sectionSpacing)
        }
        .themedBackground()
        .navigationTitle("SSL Monitor")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        .accessibilityIdentifier("screen_sslCertificateMonitor")
        .task { await viewModel.loadTrackedDomains() }
    }

    // MARK: - Mode Picker

    private var modePicker: some View {
        Picker("Mode", selection: $selectedTab) {
            Text("Query").tag(0)
            Text("Watch List (\(viewModel.trackedDomains.count))").tag(1)
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("sslMonitor_picker_view")
    }

    // MARK: - Query Section

    private var querySection: some View {
        VStack(spacing: Theme.Layout.sectionSpacing) {
            domainInputCard
            if viewModel.isLoading {
                loadingView
            } else if let error = viewModel.errorMessage {
                errorView(error)
            } else if let result = viewModel.currentResult {
                resultCards(result)
            }
        }
    }

    private var domainInputCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Domain")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ToolInputField(
                text: $viewModel.domain,
                placeholder: "example.com",
                icon: "lock.shield",
                keyboardType: .URL,
                accessibilityID: "ssl_monitor_input_domain",
                onSubmit: {
                    if viewModel.canQuery {
                        Task { await viewModel.queryDomain() }
                    }
                }
            )

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Port")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField("443", text: $viewModel.port)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .frame(width: 60)
                        .accessibilityIdentifier("sslMonitor_textfield_port")
                }

                Spacer()

                Button {
                    Task { await viewModel.queryDomain() }
                } label: {
                    Label("Query", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.Colors.accent)
                .disabled(!viewModel.canQuery)
                .accessibilityIdentifier("sslMonitor_button_query")
            }
        }
    }

    private var loadingView: some View {
        GlassCard {
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: Theme.Colors.accent))
                Text("Checking certificate…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
    }

    private func errorView(_ message: String) -> some View {
        GlassCard {
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.Colors.error)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("sslMonitor_label_error")
    }

    @ViewBuilder
    private func resultCards(_ result: DomainExpirationStatus) -> some View {
        // SSL Certificate Card
        if let ssl = result.sslCertificate {
            sslCertificateCard(ssl, domain: result.domain)
        } else if let sslErr = result.sslError {
            GlassCard {
                Label("SSL: \(sslErr)", systemImage: "exclamationmark.lock")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("sslMonitor_card_sslError")
        }

        // WHOIS Card
        if let whois = result.whoisResult {
            whoisCard(whois)
        } else if let whoisErr = result.whoisError {
            GlassCard {
                Label("WHOIS: \(whoisErr)", systemImage: "exclamationmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("sslMonitor_card_whoisError")
        }

        // Add to watch list
        if result.sslCertificate != nil || result.whoisResult != nil {
            addToWatchListButton(result)
        }
    }

    private func sslCertificateCard(_ ssl: SSLCertificateInfo, domain _: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("SSL Certificate", systemImage: "lock.shield.fill")
                        .font(.headline)
                        .foregroundStyle(ssl.isValid ? Theme.Colors.success : Theme.Colors.error)
                    Spacer()
                    statusBadge(ssl.isValid ? "Valid" : "Invalid", color: ssl.isValid ? .green : .red)
                }

                Divider().background(Theme.Colors.glassBorder)

                certRow(label: "Subject", value: ssl.subject)
                certRow(label: "Issuer", value: ssl.issuer)
                certRow(label: "Expires", value: ssl.validTo.formatted(date: .abbreviated, time: .omitted))
                certRow(
                    label: "Days Left",
                    value: "\(ssl.daysUntilExpiry) days",
                    valueColor: expiryColor(days: ssl.daysUntilExpiry)
                )
            }
        }
        .accessibilityIdentifier("sslMonitor_card_ssl")
    }

    private func whoisCard(_ whois: WHOISResult) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Label("Domain Registration", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Divider().background(Theme.Colors.glassBorder)

                if let registrar = whois.registrar {
                    certRow(label: "Registrar", value: registrar)
                }
                if let expDate = whois.expirationDate {
                    certRow(label: "Expires", value: expDate.formatted(date: .abbreviated, time: .omitted))
                    let days = Calendar.current.dateComponents([.day], from: Date(), to: expDate).day ?? 0
                    certRow(label: "Days Left", value: "\(max(0, days)) days", valueColor: expiryColor(days: days))
                }
                if let created = whois.creationDate {
                    certRow(label: "Registered", value: created.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
        .accessibilityIdentifier("sslMonitor_card_whois")
    }

    private func addToWatchListButton(_ _: DomainExpirationStatus) -> some View {
        VStack(spacing: 12) {
            if viewModel.showingAddToWatchList {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Add to Watch List")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundStyle(Theme.Colors.textPrimary)

                        TextField("Notes (optional)", text: $viewModel.notes)
                            .textFieldStyle(.plain)
                            .font(.subheadline)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .accessibilityIdentifier("sslMonitor_textfield_notes")

                        HStack(spacing: 12) {
                            Button("Cancel") {
                                viewModel.showingAddToWatchList = false
                                viewModel.notes = ""
                            }
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .accessibilityIdentifier("sslMonitor_button_cancelAdd")

                            Spacer()

                            Button("Add") {
                                Task { await viewModel.addToWatchList() }
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.Colors.accent)
                            .accessibilityIdentifier("sslMonitor_button_confirmAdd")
                        }
                    }
                }
            } else {
                Button {
                    viewModel.showingAddToWatchList = true
                } label: {
                    Label("Add to Watch List", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.Colors.accent)
                .accessibilityIdentifier("sslMonitor_button_add")
            }
        }
    }

    // MARK: - Watch List Section

    private var watchListSection: some View {
        VStack(alignment: .leading, spacing: Theme.Layout.sectionSpacing) {
            HStack {
                Text("Tracked Domains")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)

                Spacer()

                Button {
                    Task { await viewModel.refreshAll() }
                } label: {
                    if viewModel.isLoading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Label("Refresh All", systemImage: "arrow.clockwise")
                            .font(.caption)
                    }
                }
                .disabled(viewModel.isLoading)
                .foregroundStyle(Theme.Colors.accent)
                .accessibilityIdentifier("sslMonitor_button_refreshAll")
            }
            .accessibilityIdentifier("sslMonitor_section_watchlist")

            if viewModel.trackedDomains.isEmpty {
                watchListEmptyState
            } else {
                watchListRows
            }
        }
    }

    private var watchListEmptyState: some View {
        GlassCard {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.title)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Text("No domains tracked")
                    .font(.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text("Query a domain and add it to your watch list")
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .accessibilityIdentifier("sslMonitor_label_watchlistEmpty")
    }

    private var watchListRows: some View {
        GlassCard {
            VStack(spacing: 0) {
                ForEach(Array(viewModel.trackedDomains.enumerated()), id: \.element.id) { index, status in
                    WatchListRow(status: status) {
                        Task { await viewModel.removeFromWatchList(domain: status.domain) }
                    }
                    .accessibilityIdentifier("sslMonitor_row_\(status.domain)")

                    if index < viewModel.trackedDomains.count - 1 {
                        Divider()
                            .background(Theme.Colors.glassBorder)
                    }
                }
            }
        }
    }

    // MARK: - Shared Helpers

    private func certRow(label: String, value: String, valueColor: Color = Theme.Colors.textPrimary) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption)
                .fontDesign(.monospaced)
                .foregroundStyle(valueColor)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusBadge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .fontWeight(.semibold)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func expiryColor(days: Int) -> Color {
        if days <= 7 { return Theme.Colors.error }
        if days <= 30 { return Theme.Colors.warning }
        return Theme.Colors.success
    }
}

// MARK: - Watch List Row

private struct WatchListRow: View {
    let status: DomainExpirationStatus
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: sslIcon)
                .foregroundStyle(sslColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(status.domain)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let notes = status.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }

                HStack(spacing: 8) {
                    if let days = status.sslDaysUntilExpiration {
                        expiryLabel("SSL", days: days)
                    }
                    if let days = status.domainDaysUntilExpiration {
                        expiryLabel("Domain", days: days)
                    }
                }
            }

            Spacer()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.Colors.error)
            .accessibilityIdentifier("sslMonitor_button_delete\(status.domain)")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
    }

    private var sslIcon: String {
        guard let days = status.sslDaysUntilExpiration else { return "questionmark.circle" }
        if days <= 7 { return "xmark.shield" }
        if days <= 30 { return "exclamationmark.shield" }
        return "checkmark.shield"
    }

    private var sslColor: Color {
        guard let days = status.sslDaysUntilExpiration else { return .gray }
        if days <= 7 { return Theme.Colors.error }
        if days <= 30 { return Theme.Colors.warning }
        return Theme.Colors.success
    }

    private func expiryLabel(_ label: String, days: Int) -> some View {
        let color: Color = days <= 7 ? Theme.Colors.error : days <= 30 ? Theme.Colors.warning : Theme.Colors.success
        return Text("\(label) \(days)d")
            .font(.caption2)
            .foregroundStyle(color)
    }
}

#Preview {
    NavigationStack {
        SSLCertificateMonitorView()
    }
}
