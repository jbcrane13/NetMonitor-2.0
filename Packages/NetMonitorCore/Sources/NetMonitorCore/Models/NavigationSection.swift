import Foundation

/// Sidebar navigation sections for the macOS app.
/// Defined in Core so it can be referenced from shared ViewModels if needed;
/// iOS tab navigation uses a different approach.
public enum NavigationSection: String, CaseIterable, Identifiable, Sendable {
    case devices   = "Devices"
    case tools     = "Tools"
    case settings  = "Settings"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .devices:   "list.bullet.rectangle"
        case .tools:     "wrench.and.screwdriver"
        case .settings:  "gearshape"
        }
    }
}
