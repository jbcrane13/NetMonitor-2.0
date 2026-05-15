import SwiftUI

// MARK: - AppDestination

/// Typed navigation destinations for the iOS app's `NavigationStack` hierarchy.
///
/// Standardizes value-based routing across the Dashboard, Devices, and
/// Network Map tabs. Adding a new destination is a four-step process:
/// 1. Add a case here.
/// 2. Add the corresponding `case` in ``AppDestinationModifier``.
/// 3. Replace the legacy `NavigationLink(destination:)` at the call site with
///    `NavigationLink(value: AppDestination.<case>)`.
/// 4. Make sure the originating `NavigationStack` has `.appDestinations()`
///    installed on its root content.
enum AppDestination: Hashable {
    case deviceDetail(ipAddress: String)
    case ping(host: String)
    case portScanner(host: String)
    case dnsLookup(domain: String)
    case wakeOnLAN(mac: String)
    case speedTest
    case heatmapSurvey
}

// MARK: - View Modifier

private struct AppDestinationModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationDestination(for: AppDestination.self) { destination in
            switch destination {
            case .deviceDetail(let ip):
                DeviceDetailView(ipAddress: ip)
            case .ping(let host):
                PingToolView(initialHost: host)
            case .portScanner(let host):
                PortScannerToolView(initialHost: host)
            case .dnsLookup(let domain):
                DNSLookupToolView(initialDomain: domain)
            case .wakeOnLAN(let mac):
                WakeOnLANToolView(initialMacAddress: mac)
            case .speedTest:
                SpeedTestToolView()
            case .heatmapSurvey:
                HeatmapSurveyView()
            }
        }
    }
}

extension View {
    /// Registers the canonical ``AppDestination`` map on this view's enclosing
    /// `NavigationStack`. Apply once at the root of every tab that uses
    /// value-based `NavigationLink(value:)` to ``AppDestination``.
    func appDestinations() -> some View {
        modifier(AppDestinationModifier())
    }
}
