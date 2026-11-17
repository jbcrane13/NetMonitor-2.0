import SwiftUI
import NetMonitorCore

/// Health checks (#397) and DNS speed comparison (#399) for the local network dashboard.
struct HealthChecklistCard: View {
    let viewModel: NetworkHealthScoreMacViewModel
    /// Re-measures the checks; the owner supplies the Mac's current readings.
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle().fill(MacTheme.Colors.info).frame(width: 5, height: 5)
                Text("HEALTH CHECKS")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.white.opacity(0.7))
                    .tracking(1.4)
                Spacer()
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isCalculating)
                .help("Run the health checks again")
                .accessibilityLabel("Refresh health checks")
                .accessibilityIdentifier("healthChecks_button_refresh")
            }

            if viewModel.checks.isEmpty {
                Text(viewModel.isCalculating ? "Checking…" : "Checks run with the health score.")
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
            } else {
                ForEach(viewModel.checks) { check in
                    checkRow(check)
                }
            }

            Divider()

            dnsSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .macGlassCard(cornerRadius: 14, padding: 10, statusGlow: MacTheme.Colors.info)
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
        case .pass: MacTheme.Colors.success
        case .warn: MacTheme.Colors.warning
        case .unavailable: Color.white.opacity(0.5)
        }
    }

    private func checkRow(_ check: HealthCheck) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: Self.icon(for: check.status))
                .font(.caption)
                .foregroundStyle(Self.color(for: check.status))
            VStack(alignment: .leading, spacing: 1) {
                Text(check.kind.title)
                    .font(.caption.weight(.semibold))
                Text(check.message)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("healthChecks_row_\(check.kind.rawValue)")
    }

    @ViewBuilder
    private var dnsSection: some View {
        HStack {
            Text("DNS speed")
                .font(.caption.weight(.semibold))
            Spacer()
            if viewModel.isComparingDNS {
                ProgressView().controlSize(.small)
            } else {
                Button(viewModel.dnsResults.isEmpty ? "Compare" : "Run Again") {
                    Task { await viewModel.compareDNSServers() }
                }
                .controlSize(.small)
                .accessibilityIdentifier("healthChecks_button_compareDNS")
            }
        }

        ForEach(viewModel.dnsResults) { result in
            HStack(spacing: 6) {
                Text(result.server.name)
                    .font(.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                Text(result.server.address)
                    .font(.caption2)
                    .foregroundStyle(Color.white.opacity(0.5))
                Spacer()
                if result.id == viewModel.fastestDNS?.id {
                    Text("FASTEST")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(MacTheme.Colors.success)
                        .tracking(1.2)
                }
                Text(result.medianMs.map { String(format: "%.0f ms", $0) } ?? "No reply")
                    .font(.caption)
                    .fontDesign(.monospaced)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("healthChecks_dnsResult_\(result.server.name.replacingOccurrences(of: " ", with: ""))")
        }
    }
}
