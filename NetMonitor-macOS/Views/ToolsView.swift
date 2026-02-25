//
//  ToolsView.swift
//  NetMonitor
//
//  Grid launcher for network diagnostic tools.
//

import SwiftUI
import NetMonitorCore

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
        }
    }
}

struct ToolsView: View {
    @Binding var selection: SidebarSelection?

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(NetworkTool.allCases) { tool in
                    ToolCard(tool: tool)
                        .onTapGesture {
                            selection = .tool(tool)
                        }
                        .accessibilityIdentifier("tools_card_\(tool.rawValue.lowercased().replacingOccurrences(of: " ", with: "_"))")
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
        .padding(10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
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
