import SwiftUI
import NetMonitorCore
import SwiftData

struct ContentView: View {
    @State private var selectedTab: Tab = .dashboard
    // Observe ThemeManager so the entire view tree re-renders on accent color change
    @State private var themeManager = ThemeManager.shared
    
    enum Tab: String, CaseIterable {
        case dashboard
        case map
        case tools
        
        var title: String {
            switch self {
            case .dashboard: "Dashboard"
            case .map: "Map"
            case .tools: "Tools"
            }
        }
        
        var icon: String {
            switch self {
            case .dashboard: "gauge.with.dots.needle.bottom.50percent"
            case .map: "network"
            case .tools: "wrench.and.screwdriver"
            }
        }
    }
    
    var body: some View {
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
        }
        .tint(themeManager.accent)
        .accessibilityIdentifier("screen_main")
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [], inMemory: true)
}
