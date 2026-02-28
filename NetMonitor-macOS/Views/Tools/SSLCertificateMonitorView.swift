import SwiftUI
import NetMonitorCore

/// macOS SSL Certificate & Domain Expiration Monitor.
struct SSLCertificateMonitorView: View {
    @State private var domain = ""
    @State private var port = "443"
    @State private var isLoading = false
    @State private var currentResult: DomainExpirationStatus?
    @State private var trackedDomains: [DomainExpirationStatus] = []
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    @State private var notes = ""
    @State private var showAddNotes = false

    private let tracker = CertificateExpirationTracker()

    var body: some View {
        ToolSheetContainer(
            title: "SSL Monitor",
            iconName: "lock.shield",
            closeAccessibilityID: "sslMonitor_button_close",
            minWidth: 560,
            minHeight: 440,
            inputArea: { inputArea },
            outputArea: { outputArea },
            footerContent: { footer }
        )
        .task { trackedDomains = await tracker.getAllTrackedDomains() }
    }

    // MARK: - Input Area

    private var inputArea: some View {
        VStack(spacing: 8) {
            Picker("Mode", selection: $selectedTab) {
                Text("Query").tag(0)
                Text("Watch List (\(trackedDomains.count))").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier("ssl_monitor_picker_view")

            if selectedTab == 0 {
                queryInputRow
            }
        }
    }

    private var queryInputRow: some View {
        HStack(spacing: 12) {
            TextField("example.com", text: $domain)
                .textFieldStyle(.roundedBorder)
                .onSubmit { runQuery() }
                .disabled(isLoading)
                .accessibilityIdentifier("ssl_monitor_input_domain")

            TextField("443", text: $port)
                .textFieldStyle(.roundedBorder)
                .frame(width: 60)
                .disabled(isLoading)

            Button(isLoading ? "Querying…" : "Query") { runQuery() }
                .buttonStyle(.borderedProminent)
                .disabled(domain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
                .accessibilityIdentifier("ssl_monitor_button_query")
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    // MARK: - Output Area

    private var outputArea: some View {
        Group {
            if selectedTab == 0 {
                queryOutputArea
            } else {
                watchListArea
            }
        }
    }

    private var queryOutputArea: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if isLoading {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("Checking certificate…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                } else if let error = errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .padding()
                        .accessibilityIdentifier("ssl_monitor_error")
                } else if let result = currentResult {
                    resultContent(result)
                } else {
                    Text("Enter a domain to check its SSL certificate and registration status.")
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 40)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .background(Color.black.opacity(0.15))
    }

    @ViewBuilder
    private func resultContent(_ result: DomainExpirationStatus) -> some View {
        if let ssl = result.sslCertificate {
            sslSection(ssl)
        } else if let err = result.sslError {
            Label("SSL Error: \(err)", systemImage: "xmark.shield").foregroundStyle(.red)
                .accessibilityIdentifier("ssl_monitor_ssl_card")
        }

        if let whois = result.whoisResult {
            whoisSection(whois)
        } else if let err = result.whoisError {
            Label("WHOIS Error: \(err)", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                .accessibilityIdentifier("ssl_monitor_whois_card")
        }
    }

    private func sslSection(_ ssl: SSLCertificateInfo) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                infoRow("Subject", ssl.subject)
                infoRow("Issuer", ssl.issuer)
                infoRow("Valid From", ssl.validFrom.formatted(date: .abbreviated, time: .omitted))
                infoRow("Expires", ssl.validTo.formatted(date: .abbreviated, time: .omitted))
                HStack {
                    Text("Days Left")
                        .font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text("\(ssl.daysUntilExpiry) days")
                        .font(.caption).fontDesign(.monospaced)
                        .foregroundStyle(expiryColor(days: ssl.daysUntilExpiry))
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("SSL Certificate", systemImage: ssl.isValid ? "checkmark.shield.fill" : "xmark.shield.fill")
                .foregroundStyle(ssl.isValid ? .green : .red)
        }
        .accessibilityIdentifier("ssl_monitor_ssl_card")
    }

    private func whoisSection(_ whois: WHOISResult) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if let reg = whois.registrar { infoRow("Registrar", reg) }
                if let exp = whois.expirationDate {
                    infoRow("Expires", exp.formatted(date: .abbreviated, time: .omitted))
                    let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day ?? 0
                    HStack {
                        Text("Days Left").font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                        Text("\(max(0, days)) days").font(.caption).fontDesign(.monospaced).foregroundStyle(expiryColor(days: days))
                    }
                }
                if let created = whois.creationDate {
                    infoRow("Registered", created.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .padding(.vertical, 4)
        } label: {
            Label("Domain Registration", systemImage: "doc.text.magnifyingglass")
        }
        .accessibilityIdentifier("ssl_monitor_whois_card")
    }

    private var watchListArea: some View {
        Group {
            if trackedDomains.isEmpty {
                Text("No domains tracked. Query a domain and add it to the watch list.")
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding()
                    .accessibilityIdentifier("ssl_monitor_watchlist_empty")
            } else {
                List(trackedDomains) { status in
                    watchListRow(status)
                        .accessibilityIdentifier("ssl_monitor_watchlist_row_\(status.domain)")
                }
                .accessibilityIdentifier("ssl_monitor_watchlist_section")
            }
        }
    }

    private func watchListRow(_ status: DomainExpirationStatus) -> some View {
        HStack {
            Image(systemName: sslIcon(for: status))
                .foregroundStyle(sslColor(for: status))

            VStack(alignment: .leading, spacing: 2) {
                Text(status.domain).fontWeight(.medium)
                if let notes = status.notes, !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let days = status.sslDaysUntilExpiration {
                Text("SSL \(days)d").font(.caption).foregroundStyle(expiryColor(days: days))
            }

            Button(role: .destructive) {
                Task {
                    await tracker.removeDomain(status.domain)
                    trackedDomains = await tracker.getAllTrackedDomains()
                }
            } label: {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            if selectedTab == 0 {
                if let result = currentResult, !isLoading {
                    if !trackedDomains.contains(where: { $0.domain == result.domain }) {
                        if showAddNotes {
                            TextField("Notes (optional)", text: $notes)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                            Button("Add") {
                                Task {
                                    await tracker.addDomain(result.domain, port: result.port, notes: notes.isEmpty ? nil : notes)
                                    trackedDomains = await tracker.getAllTrackedDomains()
                                    notes = ""
                                    showAddNotes = false
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("ssl_monitor_button_add")
                            Button("Cancel") { showAddNotes = false
                            notes = ""
                            }
                        } else {
                            Button("Add to Watch List") { showAddNotes = true }
                                .accessibilityIdentifier("ssl_monitor_button_add")
                        }
                    } else {
                        Text("In watch list").foregroundStyle(.secondary).font(.caption)
                    }
                }
            } else {
                Button {
                    Task {
                        isLoading = true
                        trackedDomains = await tracker.refreshAllDomains()
                        isLoading = false
                    }
                } label: {
                    Label("Refresh All", systemImage: "arrow.clockwise")
                }
                .disabled(isLoading)
                .accessibilityIdentifier("ssl_monitor_button_refresh_all")
            }

            Spacer()

            if isLoading { ProgressView().scaleEffect(0.7) }
        }
        .padding()
    }

    // MARK: - Helpers

    private func runQuery() {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            if let result = await tracker.refreshDomain(trimmed) {
                currentResult = result
            } else {
                errorMessage = "Could not retrieve certificate information"
            }
            isLoading = false
        }
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
            Text(value).font(.caption).fontDesign(.monospaced)
        }
    }

    private func expiryColor(days: Int) -> Color {
        if days <= 7 { return .red }
        if days <= 30 { return .orange }
        return .green
    }

    private func sslIcon(for status: DomainExpirationStatus) -> String {
        guard let days = status.sslDaysUntilExpiration else { return "questionmark.circle" }
        if days <= 7 { return "xmark.shield" }
        if days <= 30 { return "exclamationmark.shield" }
        return "checkmark.shield"
    }

    private func sslColor(for status: DomainExpirationStatus) -> Color {
        guard let days = status.sslDaysUntilExpiration else { return .gray }
        if days <= 7 { return .red }
        if days <= 30 { return .orange }
        return .green
    }
}

#Preview { SSLCertificateMonitorView() }
