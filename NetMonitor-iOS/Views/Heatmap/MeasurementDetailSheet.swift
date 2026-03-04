import NetMonitorCore
import SwiftUI

// MARK: - MeasurementDetailSheet

/// A bottom sheet showing detailed information about a measurement point.
/// Provides a delete button for point removal.
struct MeasurementDetailSheet: View {
    let point: MeasurementPoint
    let onDelete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Layout.sectionSpacing) {
                    // Signal overview
                    signalOverview

                    // Detailed measurements
                    measurementDetails

                    // Network info
                    networkInfo

                    // Delete button
                    deleteButton
                }
                .padding(.horizontal, Theme.Layout.screenPadding)
                .padding(.bottom, Theme.Layout.sectionSpacing)
            }
            .themedBackground()
            .navigationTitle("Measurement Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Theme.Colors.accent)
                }
            }
        }
        .accessibilityIdentifier("heatmap_screen_measurementDetail")
    }

    // MARK: - Signal Overview

    private var signalOverview: some View {
        GlassCard {
            VStack(spacing: 8) {
                HStack {
                    Image(systemName: "wifi")
                        .font(.title2)
                        .foregroundStyle(rssiColor)

                    Text("\(point.rssi) dBm")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .monospacedDigit()
                }

                Text(signalQualityLabel)
                    .font(.subheadline)
                    .foregroundStyle(rssiColor)

                Text(formattedTimestamp)
                    .font(.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Measurement Details

    private var measurementDetails: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Measurements", systemImage: "chart.bar.fill")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                DetailRow(label: "RSSI", value: "\(point.rssi) dBm")

                if let downloadSpeed = point.downloadSpeed {
                    DetailRow(label: "Download", value: String(format: "%.1f Mbps", downloadSpeed))
                }

                if let uploadSpeed = point.uploadSpeed {
                    DetailRow(label: "Upload", value: String(format: "%.1f Mbps", uploadSpeed))
                }

                if let latency = point.latency {
                    DetailRow(label: "Latency", value: String(format: "%.1f ms", latency))
                }

                if let linkSpeed = point.linkSpeed {
                    DetailRow(label: "Link Speed", value: "\(linkSpeed) Mbps")
                }
            }
        }
    }

    // MARK: - Network Info

    private var networkInfo: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Label("Network", systemImage: "network")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(Theme.Colors.textPrimary)

                if let ssid = point.ssid {
                    DetailRow(label: "SSID", value: ssid)
                }

                if let bssid = point.bssid {
                    DetailRow(label: "BSSID", value: bssid)
                }

                if let channel = point.channel {
                    DetailRow(label: "Channel", value: "\(channel)")
                }

                if let band = point.band {
                    DetailRow(label: "Band", value: band.rawValue)
                }

                DetailRow(
                    label: "Position",
                    value: String(format: "(%.2f, %.2f)", point.floorPlanX, point.floorPlanY)
                )
            }
        }
    }

    // MARK: - Delete Button

    private var deleteButton: some View {
        Button(role: .destructive) {
            onDelete()
            dismiss()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "trash")
                Text("Delete Measurement")
                    .fontWeight(.semibold)
            }
            .foregroundStyle(Theme.Colors.error)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: Theme.Layout.buttonCornerRadius)
                    .fill(Theme.Colors.error.opacity(0.15))
            )
        }
        .accessibilityIdentifier("heatmap_detail_delete")
    }

    // MARK: - Helpers

    private var rssiColor: Color {
        if point.rssi >= -50 {
            return Theme.Colors.success
        } else if point.rssi >= -65 {
            return Theme.Colors.success
        } else if point.rssi >= -75 {
            return Theme.Colors.warning
        } else {
            return Theme.Colors.error
        }
    }

    private var signalQualityLabel: String {
        if point.rssi >= -50 {
            return "Excellent"
        } else if point.rssi >= -65 {
            return "Good"
        } else if point.rssi >= -75 {
            return "Fair"
        } else {
            return "Poor"
        }
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: point.timestamp)
    }
}

// MARK: - DetailRow

/// A row showing a label-value pair in the measurement detail sheet.
private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
    }
}

// MARK: - Preview

#Preview {
    let point = MeasurementPoint(
        floorPlanX: 0.5,
        floorPlanY: 0.3,
        rssi: -55,
        ssid: "TestWiFi",
        bssid: "AA:BB:CC:DD:EE:FF",
        channel: 36,
        band: .band5GHz,
        downloadSpeed: 95.2,
        latency: 12.3
    )

    MeasurementDetailSheet(point: point, onDelete: {})
}
