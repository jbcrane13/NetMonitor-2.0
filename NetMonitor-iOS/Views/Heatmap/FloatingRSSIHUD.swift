import SwiftUI

// MARK: - FloatingRSSIHUD

/// A floating glass card that displays live Wi-Fi signal information.
/// Shows RSSI in dBm, SSID name, and current measurement point count.
/// Updates at 1Hz via the ViewModel's HUD polling.
struct FloatingRSSIHUD: View {
    let rssi: Int?
    let ssid: String?
    let pointCount: Int

    var body: some View {
        GlassCard(cornerRadius: 16, padding: 12) {
            HStack(spacing: 12) {
                // Signal strength icon
                signalIcon
                    .frame(width: 32, height: 32)

                // RSSI and SSID
                VStack(alignment: .leading, spacing: 2) {
                    if let rssi {
                        Text("\(rssi) dBm")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(rssiColor)
                            .monospacedDigit()
                    } else {
                        Text("No Signal")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }

                    if let ssid, !ssid.isEmpty {
                        Text(ssid)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                // Point count badge
                VStack(spacing: 2) {
                    Text("\(pointCount)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.Colors.accent)
                        .monospacedDigit()

                    Text("points")
                        .font(.caption2)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .accessibilityIdentifier("heatmap_survey_rssiHUD")
    }

    // MARK: - Signal Icon

    private var signalIcon: some View {
        Image(systemName: signalIconName)
            .font(.title3)
            .foregroundStyle(rssiColor)
    }

    private var signalIconName: String {
        guard let rssi else { return "wifi.slash" }
        if rssi >= -50 {
            return "wifi"
        } else if rssi >= -65 {
            return "wifi"
        } else {
            return "wifi.exclamationmark"
        }
    }

    private var rssiColor: Color {
        guard let rssi else { return Theme.Colors.textTertiary }
        if rssi >= -50 {
            return Theme.Colors.success
        } else if rssi >= -65 {
            return Theme.Colors.success
        } else if rssi >= -75 {
            return Theme.Colors.warning
        } else {
            return Theme.Colors.error
        }
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Theme.Colors.backgroundBase.ignoresSafeArea()

        VStack(spacing: 16) {
            FloatingRSSIHUD(rssi: -45, ssid: "HomeWiFi", pointCount: 5)
            FloatingRSSIHUD(rssi: -72, ssid: "Office_5G", pointCount: 12)
            FloatingRSSIHUD(rssi: nil, ssid: nil, pointCount: 0)
        }
        .padding()
    }
}
