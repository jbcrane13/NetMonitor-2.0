//
//  ToolsView.swift
//  NetMonitor
//
//  Grid launcher for network diagnostic tools, organized by category.
//

import SwiftUI
import NetMonitorCore

// MARK: - Tool Category

/// Groups network tools into logical categories for easier scanning.
enum ToolCategory: String, CaseIterable, Identifiable {
    case diagnostics = "Diagnostics"
    case discovery   = "Discovery"
    case monitoring  = "Monitoring"
    case actions     = "Actions"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .diagnostics: return "stethoscope"
        case .discovery:   return "magnifyingglass.circle"
        case .monitoring:  return "chart.line.uptrend.xyaxis"
        case .actions:     return "bolt.circle"
        }
    }

    var tools: [NetworkTool] {
        switch self {
        case .diagnostics: return [.ping, .traceroute, .dnsLookup, .whois]
        case .discovery:   return [.portScanner, .bonjourBrowser, .subnetCalculator]
        case .monitoring:  return [.speedTest, .worldPing, .sslMonitor, .wifiHeatmap]
        case .actions:     return [.wakeOnLan, .geoTrace]
        }
    }
}

// MARK: - Available network tools

/// Available network tools
enum NetworkTool: String, CaseIterable, Identifiable {
    case ping = "Ping"
    case traceroute = "Traceroute"
    case portScanner = "Port Scanner"
    case dnsLookup = "DNS Lookup"
    case whois = "WHOIS"
    case speedTest = "Speed Test"
    case bonjourBrowser = "Bonjour Browser"
    case wakeOnLan = "Wake on LAN"
    case subnetCalculator = "Subnet Calculator"
    case worldPing = "World Ping"
    case geoTrace = "Geo Trace"
    case sslMonitor = "SSL Monitor"
    case wifiHeatmap = "WiFi Heatmap"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .ping: return "waveform.path"
        case .traceroute: return "point.topleft.down.to.point.bottomright.curvepath"
        case .portScanner: return "network"
        case .dnsLookup: return "magnifyingglass"
        case .whois: return "doc.text.magnifyingglass"
        case .speedTest: return "speedometer"
        case .bonjourBrowser: return "bonjour"
        case .wakeOnLan: return "power"
        case .subnetCalculator: return "square.split.bottomrightquarter"
        case .worldPing: return "globe.americas"
        case .geoTrace: return "map"
        case .sslMonitor: return "lock.shield"
        case .wifiHeatmap: return "wifi"
        }
    }

    var description: String {
        switch self {
        case .ping: return "Test host reachability"
        case .traceroute: return "Trace network path"
        case .portScanner: return "Scan open ports"
        case .dnsLookup: return "Query DNS records"
        case .whois: return "Domain information"
        case .speedTest: return "Measure connection speed"
        case .bonjourBrowser: return "Discover local services"
        case .wakeOnLan: return "Wake network devices"
        case .subnetCalculator: return "Calculate subnet ranges"
        case .worldPing: return "Global latency check"
        case .geoTrace: return "Visual route on map"
        case .sslMonitor: return "Certificate expiry check"
        case .wifiHeatmap: return "Survey WiFi coverage"
        }
    }
}

// MARK: - Tools View

struct ToolsView: View {
    @Binding var selection: SidebarSelection?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(ToolCategory.allCases) { category in
                    VStack(alignment: .leading, spacing: 12) {
                        // Section header
                        HStack(spacing: 6) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(MacTheme.Colors.textTertiary)
                            Text(category.rawValue.uppercased())
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(MacTheme.Colors.textTertiary)
                                .tracking(1.2)
                        }
                        .padding(.leading, 4)
                        .accessibilityIdentifier("tools_section_\(category.rawValue.lowercased())")

                        // Tool cards grid
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(category.tools) { tool in
                                ToolCard(tool: tool)
                                    .onTapGesture {
                                        selection = .tool(tool)
                                    }
                                    .accessibilityIdentifier("tools_card_\(tool.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))")
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Network Tools")
    }
}

// MARK: - Tool Card

struct ToolCard: View {
    let tool: NetworkTool
    @Environment(\.appAccentColor) private var accentColor
    @State private var isHovering = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: tool.iconName)
                .font(.system(size: 28))
                .foregroundStyle(accentColor)
                .frame(height: 32)

            Text(tool.rawValue)
                .font(.headline)
                .lineLimit(2)
                .minimumScaleFactor(0.75)
                .multilineTextAlignment(.center)

            Text(tool.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(minWidth: 110, maxWidth: 160, minHeight: 110)
        .macGlassCard(padding: 10)
        .overlay(
            RoundedRectangle(cornerRadius: MacTheme.Layout.cardCornerRadius)
                .strokeBorder(isHovering ? accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
        .scaleEffect(isHovering ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}

#Preview {
    ToolsView(selection: .constant(.section(.tools)))
}
