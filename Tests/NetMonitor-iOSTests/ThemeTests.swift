import SwiftUI
import Testing
@testable import NetMonitor_iOS

// MARK: - Theme.Layout Constants

@Suite("Theme.Layout")
struct ThemeLayoutTests {
    @Test func cornerRadii() {
        #expect(Theme.Layout.cardCornerRadius == 20)
        #expect(Theme.Layout.buttonCornerRadius == 12)
        #expect(Theme.Layout.smallCornerRadius == 8)
    }

    @Test func spacing() {
        #expect(Theme.Layout.cardPadding == 16)
        #expect(Theme.Layout.screenPadding == 16)
        #expect(Theme.Layout.itemSpacing == 12)
        #expect(Theme.Layout.sectionSpacing == 20)
    }

    @Test func iconSizes() {
        #expect(Theme.Layout.iconSize == 24)
        #expect(Theme.Layout.largeIconSize == 32)
        #expect(Theme.Layout.smallIconSize == 16)
    }

    @Test func componentConstants() {
        #expect(Theme.Layout.topologyHeight == 300)
        #expect(Theme.Layout.maxTopologyDevices == 8)
        #expect(Theme.Layout.signalBarWidth == 4)
        #expect(Theme.Layout.heroFontSize == 36)
    }

    @Test func resultColumnWidths() {
        #expect(Theme.Layout.resultColumnSmall == 30)
        #expect(Theme.Layout.resultColumnMedium == 50)
        #expect(Theme.Layout.resultColumnLarge == 60)
    }
}

// MARK: - Theme.Thresholds

@Suite("Theme.Thresholds")
struct ThemeThresholdsTests {
    @Test func latencyThresholds() {
        #expect(Theme.Thresholds.latencyGood == 50.0)
        #expect(Theme.Thresholds.latencyWarning == 150.0)
    }
}

// MARK: - Theme.Shadows

@Suite("Theme.Shadows")
struct ThemeShadowsTests {
    @Test func shadowRadii() {
        #expect(Theme.Shadows.cardRadius == 15)
        #expect(Theme.Shadows.cardY == 5)
        #expect(Theme.Shadows.glowRadius == 20)
    }
}

// MARK: - Color Hex Extension

@Suite("Color(hex:)")
struct ColorHexExtensionTests {
    @Test func sixCharHexDoesNotCrash() {
        // Verify Color can be constructed from 6-char hex without crashing
        _ = Color(hex: "FF0000")
        _ = Color(hex: "00FF00")
        _ = Color(hex: "0000FF")
        _ = Color(hex: "FFFFFF")
        _ = Color(hex: "000000")
    }

    @Test func threeCharHexDoesNotCrash() {
        _ = Color(hex: "F00")
        _ = Color(hex: "0F0")
        _ = Color(hex: "00F")
    }

    @Test func eightCharHexDoesNotCrash() {
        // 8-char ARGB
        _ = Color(hex: "FF0000FF")
        _ = Color(hex: "800000FF")
    }

    @Test func invalidHexDoesNotCrash() {
        // default case — should not crash
        _ = Color(hex: "")
        _ = Color(hex: "ZZZZZZ")
        _ = Color(hex: "12")
    }

    @Test func knownSemanticColorsAreAccessible() {
        // Verify static color properties are accessible (smoke test)
        _ = Theme.Colors.success
        _ = Theme.Colors.warning
        _ = Theme.Colors.error
        _ = Theme.Colors.info
        _ = Theme.Colors.textPrimary
        _ = Theme.Colors.textSecondary
        _ = Theme.Colors.textTertiary
        _ = Theme.Colors.glassBorder
        _ = Theme.Colors.glassHighlight
        _ = Theme.Colors.online
        _ = Theme.Colors.offline
        _ = Theme.Colors.idle
    }
}
