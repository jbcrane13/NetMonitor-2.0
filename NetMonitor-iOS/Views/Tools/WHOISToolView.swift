import SwiftUI
import NetMonitorCore

/// WHOIS tool view for domain and IP information lookup
struct WHOISToolView: View {
    @State private var viewModel: WHOISToolViewModel
    @State private var showRawResponse = false

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
            Text("Domain or IP")
                .font(.headline)
                .foregroundStyle(Theme.Colors.textPrimary)

            ToolInputField(
                text: $viewModel.domain,
                placeholder: "example.com or 8.8.8.8",
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
                    showRawResponse = false
                    viewModel.clearResults()
                }
            }
        }
    }

    // MARK: - Results Section

    @ViewBuilder
    private var resultsSection: some View {
        if let error = viewModel.errorMessage {
            errorSection(error)
        }

        if let result = viewModel.result {
            VStack(alignment: .leading, spacing: 12) {
                domainInfoSection(result)
                statusSection(result)
                registrantSection(result)
                domainDatesSection(result)
                nameServersSection(result)
                networkSection(result)
                rawResponseSection(result)
            }
        }
    }

    private func errorSection(_ error: String) -> some View {
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

    private func expirationColor(_ days: Int?) -> Color {
        guard let days = days else { return Theme.Colors.textPrimary }
        switch days {
        case ..<30: return Theme.Colors.error
        case 30..<90: return Theme.Colors.warning
        default: return Theme.Colors.success
        }
    }
}

// MARK: - Result Sections
//
// Split into an extension (rather than kept in the main struct body) purely to
// stay under SwiftLint's type_body_length threshold — these are still part of
// WHOISToolView's private API, just declared outside its primary declaration.
extension WHOISToolView {

    // MARK: - Domain / Registrar Info

    @ViewBuilder
    private func domainInfoSection(_ result: WHOISResult) -> some View {
        GlassCard {
            VStack(spacing: 8) {
                ToolResultRow(
                    label: result.isIPNetworkResult ? "IP Address" : "Domain",
                    value: result.query,
                    icon: result.isIPNetworkResult ? "network" : "globe",
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

                if let registrarURL = result.registrarURL {
                    Divider().background(Theme.Colors.glassBorder)
                    ToolResultRow(
                        label: "Registrar URL",
                        value: registrarURL,
                        icon: "link",
                        selectable: true
                    )
                }

                if let ianaID = result.registrarIANAID {
                    Divider().background(Theme.Colors.glassBorder)
                    ToolResultRow(
                        label: "IANA ID",
                        value: ianaID,
                        icon: "number",
                        selectable: true
                    )
                }

                if let abuseEmail = result.abuseEmail {
                    Divider().background(Theme.Colors.glassBorder)
                    ToolResultRow(
                        label: "Abuse Email",
                        value: abuseEmail,
                        icon: "exclamationmark.bubble",
                        selectable: true
                    )
                }

                if let abusePhone = result.abusePhone {
                    Divider().background(Theme.Colors.glassBorder)
                    ToolResultRow(
                        label: "Abuse Phone",
                        value: abusePhone,
                        icon: "phone",
                        selectable: true
                    )
                }
            }
        }
        .accessibilityIdentifier("whois_section_domainInfo")
    }

    // MARK: - Domain Status

    @ViewBuilder
    private func statusSection(_ result: WHOISResult) -> some View {
        if !result.status.isEmpty {
            HStack {
                Text("Status")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(result.status.enumerated()), id: \.offset) { _, status in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(status)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textPrimary)
                            if let hint = EPPStatusHints.hint(for: status) {
                                Text(hint)
                                    .font(.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                    }
                }
            }
            .accessibilityIdentifier("whois_section_status")
        }
    }

    // MARK: - Registrant

    @ViewBuilder
    private func registrantSection(_ result: WHOISResult) -> some View {
        // IP lookups already show organization/country in the Network section below —
        // skip this section there to avoid showing the same detail twice.
        if !result.isIPNetworkResult,
           result.registrantOrganization != nil || result.registrantCountry != nil || result.registrantState != nil {
            HStack {
                Text("Registrant")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            GlassCard {
                VStack(spacing: 8) {
                    if let org = result.registrantOrganization {
                        ToolResultRow(label: "Organization", value: org, icon: "building.2.crop.circle", selectable: true)
                    }
                    if let state = result.registrantState {
                        if result.registrantOrganization != nil {
                            Divider().background(Theme.Colors.glassBorder)
                        }
                        ToolResultRow(label: "State/Region", value: state, icon: "map", selectable: true)
                    }
                    if let country = result.registrantCountry {
                        if result.registrantOrganization != nil || result.registrantState != nil {
                            Divider().background(Theme.Colors.glassBorder)
                        }
                        ToolResultRow(label: "Country", value: country, icon: "flag", selectable: true)
                    }
                }
            }
            .accessibilityIdentifier("whois_section_registrant")
        }
    }

    // MARK: - Dates

    @ViewBuilder
    private func domainDatesSection(_ result: WHOISResult) -> some View {
        if result.creationDate != nil || result.expirationDate != nil || result.dnssec != nil {
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

                        if let days = result.daysUntilExpiration {
                            Divider().background(Theme.Colors.glassBorder)
                            ToolResultRow(
                                label: "Days Until Expiry",
                                value: "\(days)",
                                icon: "hourglass",
                                valueColor: expirationColor(days),
                                selectable: true
                            )
                        }
                    }

                    if let dnssec = result.dnssec {
                        Divider().background(Theme.Colors.glassBorder)
                        ToolResultRow(
                            label: "DNSSEC",
                            value: dnssec.capitalized,
                            icon: "lock.shield",
                            valueColor: dnssec.lowercased().contains("unsigned")
                                ? Theme.Colors.warning : Theme.Colors.success,
                            selectable: true
                        )
                    }
                }
            }
            .accessibilityIdentifier("whois_section_dates")
        }
    }

    // MARK: - Name Servers

    @ViewBuilder
    private func nameServersSection(_ result: WHOISResult) -> some View {
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

    // MARK: - IP Network

    @ViewBuilder
    private func networkSection(_ result: WHOISResult) -> some View {
        if result.isIPNetworkResult {
            HStack {
                Text("Network")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
            }

            GlassCard {
                VStack(spacing: 8) {
                    if let range = result.networkRange {
                        ToolResultRow(label: "Range / CIDR", value: range, icon: "network", isMonospaced: true, selectable: true)
                    }
                    if let name = result.networkName {
                        Divider().background(Theme.Colors.glassBorder)
                        ToolResultRow(label: "Network Name", value: name, icon: "tag", selectable: true)
                    }
                    if let org = result.networkOrganization {
                        Divider().background(Theme.Colors.glassBorder)
                        ToolResultRow(label: "Organization", value: org, icon: "building.2", selectable: true)
                    }
                    if let country = result.networkCountry {
                        Divider().background(Theme.Colors.glassBorder)
                        ToolResultRow(label: "Country", value: country, icon: "flag", selectable: true)
                    }
                    if let asn = result.asn {
                        Divider().background(Theme.Colors.glassBorder)
                        ToolResultRow(label: "ASN", value: asn, icon: "number.circle", selectable: true)
                    }
                }
            }
            .accessibilityIdentifier("whois_section_network")
        }
    }

    // MARK: - Raw Response

    private func rawResponseSection(_ result: WHOISResult) -> some View {
        RawResponseCard(
            title: "Raw Response",
            rawText: result.rawData,
            isExpanded: $showRawResponse,
            sectionAccessibilityID: "whois_section_rawResponse",
            disclosureAccessibilityID: "whois_disclosure_rawResponse",
            copyButtonAccessibilityID: "whois_button_copyRaw"
        )
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        WHOISToolView()
    }
}
