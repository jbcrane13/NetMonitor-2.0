import SwiftUI
import NetMonitorCore

/// Dashboard card listing the network health checks (#397) and the DNS speed comparison (#399).
struct HealthChecklistCard: View {
    let healthViewModel: NetworkHealthScoreViewModel

    var body: some View {
        GlassCard(padding: 12, statusGlow: Theme.Colors.info) {
            VStack(alignment: .leading, spacing: 10) {
                Text("HEALTH CHECKS")
                    .font(.system(.caption2, weight: .heavy))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .tracking(2.0)

                if healthViewModel.checks.isEmpty {
                    Text(healthViewModel.isCalculating ? "Checking…" : "Checks run with the health score.")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                } else {
                    ForEach(healthViewModel.checks) { check in
                        checkRow(check)
                    }
                }

                ToolInsightCard(screen: "healthScore", request: healthViewModel.insightRequest, isEmbedded: true)

                Divider().background(Theme.Colors.divider)

                dnsSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("dashboard_card_healthChecks")
    }

    private static func icon(for status: HealthCheck.Status) -> String {
        switch status {
        case .pass: "checkmark.circle.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .unavailable: "questionmark.circle"
        }
    }

    private static func color(for status: HealthCheck.Status) -> Color {
        switch status {
        case .pass: Theme.Colors.success
        case .warn: Theme.Colors.warning
        case .unavailable: Theme.Colors.textTertiary
        }
    }

    private func checkRow(_ check: HealthCheck) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: Self.icon(for: check.status))
                .font(.caption)
                .foregroundStyle(Self.color(for: check.status))
            VStack(alignment: .leading, spacing: 1) {
                Text(check.kind.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(check.message)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("dashboard_healthCheck_\(check.kind.rawValue)")
    }

    @ViewBuilder
    private var dnsSection: some View {
        HStack {
            Text("DNS speed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.Colors.textPrimary)
            Spacer()
            if healthViewModel.isComparingDNS {
                ProgressView().controlSize(.small)
            } else {
                Button(healthViewModel.dnsResults.isEmpty ? "Compare" : "Run again") {
                    Task { await healthViewModel.compareDNSServers() }
                }
                .font(.caption.weight(.semibold))
                .accessibilityIdentifier("dashboard_button_compareDNS")
            }
        }

        ForEach(healthViewModel.dnsResults) { result in
            HStack {
                Text(result.server.name)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(result.server.address)
                    .font(.caption2)
                    .foregroundStyle(Theme.Colors.textTertiary)
                Spacer()
                if result.id == healthViewModel.fastestDNS?.id {
                    Text("FASTEST")
                        .font(.system(.caption2, weight: .black))
                        .foregroundStyle(Theme.Colors.success)
                }
                Text(result.medianMs.map { String(format: "%.0f ms", $0) } ?? "No reply")
                    .font(.caption)
                    .fontDesign(.monospaced)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("dashboard_dnsResult_\(result.server.name.replacingOccurrences(of: " ", with: ""))")
        }
    }
}
