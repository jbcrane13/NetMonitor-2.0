import SwiftUI
import NetMonitorCore
import SwiftData

struct ContentView: View {
    @State private var selectedTab: Tab = .dashboard
    @State private var selectedSidebarTab: Tab? = .dashboard
    // Observe ThemeManager so the entire view tree re-renders on accent color change
    @State private var themeManager = ThemeManager.shared
    @State private var dashboardVM = DashboardViewModel()
    @Environment(\.horizontalSizeClass) var sizeClass

    enum Tab: String, CaseIterable {
        case dashboard
        case map
        case tools
        case timeline

        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .map: "Map"
            case .tools: "Tools"
            case .timeline: "Timeline"
            }
        }

        var icon: String {
            switch self {
            case .dashboard: "gauge.with.dots.needle.bottom.50percent"
            case .map: "network"
            case .tools: "wrench.and.screwdriver"
            case .timeline: "clock.arrow.circlepath"
            }
        }
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                NavigationSplitView {
                    iPadSidebar
                } detail: {
                    detailView
                }
            } else {
                TabView(selection: $selectedTab) {
                    DashboardView()
                        .tabItem {
                            Label(Tab.dashboard.title, systemImage: Tab.dashboard.icon)
                        }
                        .tag(Tab.dashboard)
                        .accessibilityIdentifier("contentView_tab_dashboard")

                    NetworkMapView()
                        .tabItem {
                            Label(Tab.map.title, systemImage: Tab.map.icon)
                        }
                        .tag(Tab.map)
                        .accessibilityIdentifier("contentView_tab_map")

                    ToolsView()
                        .tabItem {
                            Label(Tab.tools.title, systemImage: Tab.tools.icon)
                        }
                        .tag(Tab.tools)
                        .accessibilityIdentifier("contentView_tab_tools")

                    TimelineView()
                        .tabItem {
                            Label(Tab.timeline.title, systemImage: Tab.timeline.icon)
                        }
                        .tag(Tab.timeline)
                        .accessibilityIdentifier("contentView_tab_timeline")
                }
            }
        }
        .preferredColorScheme(.dark)
        .tint(themeManager.accent)
        .accessibilityIdentifier("screen_main")
    }

    // MARK: - iPad Sidebar

    private var iPadSidebar: some View {
        List(selection: $selectedSidebarTab) {
            // Network status section
            Section {
                iPadNetworkStatusRow
            } header: {
                Text("NETWORK")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
            }

            // Navigation sections
            Section {
                ForEach(Tab.allCases, id: \.self) { tab in
                    iPadSidebarRow(tab: tab)
                        .tag(tab)
                        .accessibilityIdentifier("contentView_sidebar_\(tab.rawValue)")
                }
            } header: {
                Text("NAVIGATE")
                    .font(.system(size: 10, weight: .black))
                    .tracking(1.2)
            }
        }
        .scrollContentBackground(.hidden)
        .background(.ultraThinMaterial)
        .navigationTitle("NetMonitor")
    }

    /// Network status summary row at the top of the iPad sidebar
    private var iPadNetworkStatusRow: some View {
        HStack(spacing: 10) {
            // Connection type icon
            ZStack {
                Circle()
                    .fill(dashboardVM.isConnected ? themeManager.accent.opacity(0.15) : Color.gray.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: dashboardVM.isConnected ? dashboardVM.connectionTypeIcon : "wifi.slash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(dashboardVM.isConnected ? themeManager.accent : .gray)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(dashboardVM.networkName.isEmpty ? "No Network" : dashboardVM.networkName)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)

                    if dashboardVM.isConnected {
                        Text("ACTIVE")
                            .font(.system(size: 8, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 8) {
                    if dashboardVM.deviceCount > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "desktopcomputer")
                                .font(.system(size: 9))
                            Text("\(dashboardVM.deviceCount)")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                    }

                    if let latency = dashboardVM.gatewayLatency {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                                .font(.system(size: 9))
                            Text(latency < 1 ? "<1ms" : "\(Int(latency))ms")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                        }
                        .foregroundStyle(latency < 20 ? .green : latency < 80 ? .yellow : .red)
                    }
                }
            }

            Spacer()
        }
    }

    /// Enhanced sidebar row for iPad with selection indicator
    private func iPadSidebarRow(tab: Tab) -> some View {
        HStack(spacing: 10) {
            // Selection indicator bar
            if selectedSidebarTab == tab {
                RoundedRectangle(cornerRadius: 2)
                    .fill(themeManager.accent)
                    .frame(width: 3, height: 16)
            } else {
                Spacer().frame(width: 3)
            }

            Image(systemName: tab.icon)
                .font(.system(size: 14, weight: selectedSidebarTab == tab ? .bold : .medium))
                .foregroundStyle(selectedSidebarTab == tab ? themeManager.accent : .secondary)
                .frame(width: 20)

            Text(tab.title)
                .font(.system(size: 14, weight: selectedSidebarTab == tab ? .semibold : .regular))

            Spacer()

            // Badge for tools — show category count
            if tab == .tools {
                Text("\(IOSToolCategory.allCases.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedSidebarTab ?? .dashboard {
        case .dashboard: DashboardView()
        case .map: NetworkMapView()
        case .tools: ToolsView()
        case .timeline: TimelineView()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [], inMemory: true)
}
