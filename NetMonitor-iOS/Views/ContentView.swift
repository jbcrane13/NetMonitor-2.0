import SwiftUI
import NetMonitorCore
import SwiftData

struct ContentView: View {
    @State private var selectedTab: Tab = .dashboard
    @State private var selectedSidebarTab: Tab? = .dashboard
    // Observe ThemeManager so the entire view tree re-renders on accent color change
    @State private var themeManager = ThemeManager.shared
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
        if sizeClass == .regular {
            NavigationSplitView {
                List(Tab.allCases, id: \.self, selection: $selectedSidebarTab) { tab in
                    Label(tab.title, systemImage: tab.icon)
                        .accessibilityIdentifier("contentView_sidebar_\(tab.rawValue)")
                }
                .navigationTitle("NetMonitor")
            } detail: {
                detailView
            }
            .tint(themeManager.accent)
            .accessibilityIdentifier("screen_main")
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
            .tint(themeManager.accent)
            .accessibilityIdentifier("screen_main")
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
