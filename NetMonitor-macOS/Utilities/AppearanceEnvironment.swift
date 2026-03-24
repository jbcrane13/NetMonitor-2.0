import SwiftUI

// MARK: - Companion Service

private struct CompanionServiceKey: EnvironmentKey {
    static let defaultValue: CompanionService? = nil
}

extension EnvironmentValues {
    var companionService: CompanionService? {
        get { self[CompanionServiceKey.self] }
        set { self[CompanionServiceKey.self] = newValue }
    }
}

// MARK: - Accent Color

private struct AppAccentColorKey: EnvironmentKey {
    static let defaultValue: Color = .cyan
}

extension EnvironmentValues {
    var appAccentColor: Color {
        get { self[AppAccentColorKey.self] }
        set { self[AppAccentColorKey.self] = newValue }
    }
}

// MARK: - Compact Mode

private struct CompactModeKey: EnvironmentKey {
    static let defaultValue: Bool = false
}

extension EnvironmentValues {
    var compactMode: Bool {
        get { self[CompactModeKey.self] }
        set { self[CompactModeKey.self] = newValue }
    }
}
