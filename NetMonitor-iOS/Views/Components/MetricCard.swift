import SwiftUI
import NetMonitorCore

// MARK: - Metric Card
/// A compact card displaying a single metric with icon, label, and value
struct MetricCard: View {
    let icon: String
    let label: String
    let value: String
    var subtitle: String? = nil
    var iconColor: Color = Theme.Colors.accent
    var trend: Trend? = nil
    
    enum Trend {
        case up, down, stable
        
        var icon: String {
            switch self {
            case .up: "arrow.up.right"
            case .down: "arrow.down.right"
            case .stable: "arrow.right"
            }
        }
        
        var color: Color {
            switch self {
            case .up: Theme.Colors.success
            case .down: Theme.Colors.error
            case .stable: Theme.Colors.textSecondary
            }
        }
    }
    
    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Layout.smallCornerRadius) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: Theme.Layout.iconSize))
                        .foregroundStyle(iconColor)
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(iconColor.opacity(0.2))
                        )
                    
                    Spacer()
                    
                    if let trend {
                        Image(systemName: trend.icon)
                            .font(.caption)
                            .foregroundStyle(trend.color)
                    }
                }
                
                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(Theme.Colors.textTertiary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("metricCard_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))")
        .accessibilityLabel("\(label): \(value)")
    }
}

// MARK: - Large Metric Card
/// A larger metric card with more prominence
struct LargeMetricCard: View {
    let icon: String
    let label: String
    let value: String
    var unit: String? = nil
    var iconColor: Color = Theme.Colors.accent
    var status: StatusType? = nil
    
    var body: some View {
        GlassCard {
            VStack(spacing: Theme.Layout.itemSpacing) {
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: Theme.Layout.largeIconSize))
                        .foregroundStyle(iconColor)
                    
                    Spacer()
                    
                    if let status {
                        StatusBadge(status: status, size: .small)
                    }
                }
                
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(value)
                            .font(.system(size: Theme.Layout.heroFontSize, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                        
                        if let unit {
                            Text(unit)
                                .font(.headline)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                    }
                    
                    Text(label)
                        .font(.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("largeMetricCard_\(label.lowercased().replacingOccurrences(of: " ", with: "_"))")
        .accessibilityLabel("\(label): \(value) \(unit ?? "")")
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Theme.Gradients.background
            .ignoresSafeArea()
        
        ScrollView {
            VStack(spacing: 20) {
                Text("Metric Cards")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    MetricCard(
                        icon: "wifi",
                        label: "Signal Strength",
                        value: "-45 dBm",
                        subtitle: "Excellent",
                        iconColor: Theme.Colors.success
                    )
                    
                    MetricCard(
                        icon: "arrow.up.arrow.down",
                        label: "Latency",
                        value: "12 ms",
                        trend: .stable
                    )
                    
                    MetricCard(
                        icon: "desktopcomputer",
                        label: "Devices",
                        value: "24",
                        subtitle: "Online"
                    )
                    
                    MetricCard(
                        icon: "target",
                        label: "Targets",
                        value: "5/6",
                        iconColor: Theme.Colors.warning,
                        trend: .down
                    )
                }
                
                Text("Large Metric Card")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                LargeMetricCard(
                    icon: "speedometer",
                    label: "Download Speed",
                    value: "245.8",
                    unit: "Mbps",
                    iconColor: Theme.Colors.success,
                    status: .online
                )
                
                Text("Metric Rows")
                    .font(.headline)
                    .foregroundStyle(Theme.Colors.textPrimary)
                
                GlassCard {
                    VStack(spacing: 12) {
                        ToolResultRow(label: "IP Address", value: "192.168.1.100", icon: "network", isMonospaced: true)
                        Divider().background(Theme.Colors.glassBorder)
                        ToolResultRow(label: "MAC Address", value: "AA:BB:CC:DD:EE:FF", icon: "barcode", isMonospaced: true)
                        Divider().background(Theme.Colors.glassBorder)
                        ToolResultRow(label: "Status", value: "Online", icon: "circle.fill", valueColor: Theme.Colors.success)
                    }
                }
            }
            .padding()
        }
    }
}
