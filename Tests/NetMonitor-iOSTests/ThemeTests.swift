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
        let _ = Color(hex: "FF0000")
        let _ = Color(hex: "00FF00")
        let _ = Color(hex: "0000FF")
        let _ = Color(hex: "FFFFFF")
        let _ = Color(hex: "000000")
    }

    @Test func threeCharHexDoesNotCrash() {
        let _ = Color(hex: "F00")
        let _ = Color(hex: "0F0")
        let _ = Color(hex: "00F")
    }

    @Test func eightCharHexDoesNotCrash() {
        // 8-char ARGB
        let _ = Color(hex: "FF0000FF")
        let _ = Color(hex: "800000FF")
    }

    @Test func invalidHexDoesNotCrash() {
        // default case — should not crash
        let _ = Color(hex: "")
        let _ = Color(hex: "ZZZZZZ")
        let _ = Color(hex: "12")
    }

    @Test func knownSemanticColorsAreAccessible() {
        // Verify static color properties are accessible (smoke test)
        let _ = Theme.Colors.success
        let _ = Theme.Colors.warning
        let _ = Theme.Colors.error
        let _ = Theme.Colors.info
        let _ = Theme.Colors.textPrimary
        let _ = Theme.Colors.textSecondary
        let _ = Theme.Colors.textTertiary
        let _ = Theme.Colors.glassBorder
        let _ = Theme.Colors.glassHighlight
        let _ = Theme.Colors.online
        let _ = Theme.Colors.offline
        let _ = Theme.Colors.idle
    }
}
