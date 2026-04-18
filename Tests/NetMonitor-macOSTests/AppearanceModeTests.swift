import Foundation
import Testing
@testable import NetMonitor_macOS

struct AppearanceModeTests {

    /// Regression guard for GH-142: `@AppStorage("netmonitor.appearance.theme")`
    /// reads the raw string from UserDefaults. If the enum raw values, display
    /// names, or icon names are refactored without care, the picker will silently
    /// fall back to `.system` for existing users.
    @Test func rawValuesAreStable() {
        #expect(AppearanceMode.system.rawValue == "system")
        #expect(AppearanceMode.dark.rawValue == "dark")
        #expect(AppearanceMode.light.rawValue == "light")
    }

    @Test func rawValueRoundTripSucceedsForAllCases() {
        for mode in AppearanceMode.allCases {
            let reconstructed = AppearanceMode(rawValue: mode.rawValue)
            #expect(reconstructed == mode, "AppearanceMode.\(mode) did not round-trip")
        }
    }

    @Test func rawValueInitReturnsNilForGarbageInput() {
        #expect(AppearanceMode(rawValue: "") == nil)
        #expect(AppearanceMode(rawValue: "Light") == nil) // case-sensitive
        #expect(AppearanceMode(rawValue: "auto") == nil)
    }

    @Test func displayNamesAreDistinct() {
        let names = Set(AppearanceMode.allCases.map(\.displayName))
        #expect(names.count == AppearanceMode.allCases.count)
    }

    @Test func iconNamesAreDistinct() {
        let icons = Set(AppearanceMode.allCases.map(\.iconName))
        #expect(icons.count == AppearanceMode.allCases.count)
    }
}
