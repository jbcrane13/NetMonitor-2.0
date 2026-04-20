import SwiftUI
import NetMonitorCore

// MARK: - Device Card View (Consumer Mode)

struct DeviceCardView: View {
    let device: LocalDevice
    let isSelected: Bool

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // Status indicator and icon
                ZStack {
                    Circle()
                        .fill(device.status == .online ? MacTheme.Colors.success.opacity(0.2) : Color.gray.opacity(0.2))
                        .frame(width: 48, height: 48)

                    Image(systemName: device.deviceType.iconName)
                        .font(.title3)
                        .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .gray)
                }

                // Device info
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(device.displayName)
                            .font(.headline)
                            .lineLimit(1)

                        if device.isGateway {
                            Text("Gateway")
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(MacTheme.Colors.info.opacity(0.2))
                                .foregroundStyle(MacTheme.Colors.info)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Text(device.ipAddress)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()

                        if let vendor = device.vendor {
                            Text("·")
                                .foregroundStyle(.tertiary)
                            Text(vendor)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()

                // Connection info
                VStack(alignment: .trailing, spacing: 4) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(device.status == .online ? MacTheme.Colors.success : Color.gray)
                            .frame(width: 8, height: 8)

                        Text(device.status == .online ? "Online" : "Offline")
                            .font(.caption)
                            .foregroundStyle(device.status == .online ? MacTheme.Colors.success : .secondary)
                    }

                    if let latency = device.lastLatency {
                        Text(latencyText(latency))
                            .font(.caption2)
                            .foregroundStyle(MacTheme.Colors.latencyColor(ms: latency))
                    }
                }
            }
            .padding(12)

            // Latency sparkline — shown when 2+ readings exist
            if device.latencyHistory.count > 1 {
                MiniSparklineView(
                    data: device.latencyHistory,
                    lineWidth: 1.2,
                    showPulse: true,
                    height: 20,
                    cornerRadius: 4,
                    thresholdColor: { MacTheme.Colors.latencyColor(ms: $0) }
                )
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .opacity(colorScheme == .dark ? 0.8 : 0.7)
                RoundedRectangle(cornerRadius: 12)
                    .fill(MacTheme.Colors.glassBackground)
                LinearGradient(
                    colors: colorScheme == .dark
                        ? [.white.opacity(0.08), .clear, .white.opacity(0.02)]
                        : [.white.opacity(0.6), .white.opacity(0.15), .white.opacity(0.35)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isSelected
                        ? Color.accentColor
                        : MacTheme.Colors.glassBorder,
                    lineWidth: isSelected ? 2 : 0.5
                )
        )
        .shadow(
            color: MacTheme.Shadows.card,
            radius: colorScheme == .dark ? MacTheme.Shadows.cardRadius : MacTheme.Shadows.cardRadiusLight,
            x: 0,
            y: MacTheme.Shadows.cardY
        )
    }

    private func latencyText(_ latency: Double) -> String {
        if latency < 1 { return "<1 ms" }
        return String(format: "%.0f ms", latency)
    }
}

#Preview {
    DeviceCardView(
        device: LocalDevice(
            ipAddress: "192.168.1.1",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: "router.local",
            vendor: "Apple",
            deviceType: .router,
            status: .online,
            lastLatency: 2.5,
            isGateway: true
        ),
        isSelected: false
    )
    .padding()
}
