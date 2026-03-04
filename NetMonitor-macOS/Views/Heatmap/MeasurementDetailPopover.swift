import NetMonitorCore
import SwiftUI

// MARK: - MeasurementDetailPopover

/// Popover showing all captured data for a single measurement point.
/// Appears when clicking on an existing measurement dot on the canvas.
struct MeasurementDetailPopover: View {
    let point: MeasurementPoint
    var onDelete: (() -> Void)?

    private static let timeFormatter: DateFormatter = {
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .medium
        return fmt
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "wifi")
                    .foregroundStyle(rssiColor)
                Text("Measurement Point")
                    .font(.headline)
                Spacer()
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete this measurement point")
                .accessibilityIdentifier("heatmap_detail_delete")
            }

            Divider()

            // Signal Info
            detailSection("Signal") {
                detailRow("RSSI", value: "\(point.rssi) dBm")
                if let noise = point.noiseFloor {
                    detailRow("Noise Floor", value: "\(noise) dBm")
                }
                if let snr = point.snr {
                    detailRow("SNR", value: "\(snr) dB")
                }
            }

            // Network Info
            detailSection("Network") {
                if let ssid = point.ssid {
                    detailRow("SSID", value: ssid)
                }
                if let bssid = point.bssid {
                    detailRow("BSSID", value: bssid)
                }
                if let channel = point.channel {
                    detailRow("Channel", value: "\(channel)")
                }
                if let band = point.band {
                    detailRow("Band", value: bandDisplayName(band))
                }
                if let linkSpeed = point.linkSpeed {
                    detailRow("Link Speed", value: "\(linkSpeed) Mbps")
                }
            }

            // Speed Test Data (if active scan)
            if point.downloadSpeed != nil || point.uploadSpeed != nil || point.latency != nil {
                detailSection("Speed Test") {
                    if let dl = point.downloadSpeed {
                        detailRow("Download", value: String(format: "%.1f Mbps", dl))
                    }
                    if let ul = point.uploadSpeed {
                        detailRow("Upload", value: String(format: "%.1f Mbps", ul))
                    }
                    if let lat = point.latency {
                        detailRow("Latency", value: String(format: "%.1f ms", lat))
                    }
                }
            }

            Divider()

            // Location and Time
            HStack(spacing: 16) {
                Text(String(format: "(%.2f, %.2f)", point.floorPlanX, point.floorPlanY))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(Self.timeFormatter.string(from: point.timestamp))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 280)
        .accessibilityIdentifier("heatmap_detail_popover")
    }

    // MARK: - Helper Views

    private func detailSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
            content()
        }
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.callout)
                .fontWeight(.medium)
        }
    }

    private func bandDisplayName(_ band: WiFiBand) -> String {
        switch band {
        case .band2_4GHz: "2.4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        }
    }

    private var rssiColor: Color {
        if point.rssi >= -50 { return .green }
        if point.rssi >= -70 { return .yellow }
        return .red
    }
}

#if DEBUG
#Preview {
    MeasurementDetailPopover(
        point: MeasurementPoint(
            floorPlanX: 0.5,
            floorPlanY: 0.3,
            rssi: -55,
            noiseFloor: -90,
            snr: 35,
            ssid: "TestNetwork",
            bssid: "AA:BB:CC:DD:EE:FF",
            channel: 36,
            band: .band5GHz,
            linkSpeed: 866,
            downloadSpeed: 150.5,
            uploadSpeed: 42.3,
            latency: 8.2
        )
    )
    .padding()
}
#endif
