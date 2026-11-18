//
//  MacThemeContrastTests.swift
//  NetMonitor-macOSTests
//
//  Tests WCAG 2.1 contrast ratios for MacTheme color tokens in both dark and light modes.
//  Ensures text-on-background and UI-on-background pairs meet accessibility minimums.

import Testing
import SwiftUI
import AppKit
@testable import NetMonitor_macOS

// MARK: - WCAG 2.1 Contrast Helpers

/// Converts an sRGB channel value (0..1) to linear RGB for luminance calculation.
private func linearize(_ c: Double) -> Double {
    if c <= 0.03928 {
        return c / 12.92
    } else {
        return pow((c + 0.055) / 1.055, 2.4)
    }
}

/// Computes relative luminance per WCAG 2.1.
/// - Parameter rgb: Tuple of (red, green, blue) in sRGB 0..1 range.
/// - Returns: Relative luminance L = 0.2126*R + 0.7152*G + 0.0722*B (linear RGB).
private func relativeLuminance(r: Double, g: Double, b: Double) -> Double {
    let rLinear = linearize(r)
    let gLinear = linearize(g)
    let bLinear = linearize(b)
    return 0.2126 * rLinear + 0.7152 * gLinear + 0.0722 * bLinear
}

/// Computes WCAG 2.1 contrast ratio between two colors.
/// - Returns: Contrast ratio (lighter + 0.05) / (darker + 0.05).
private func contrastRatio(foreground: (r: Double, g: Double, b: Double),
                          background: (r: Double, g: Double, b: Double)) -> Double {
    let fgL = relativeLuminance(r: foreground.r, g: foreground.g, b: foreground.b)
    let bgL = relativeLuminance(r: background.r, g: background.g, b: background.b)
    let lighter = max(fgL, bgL)
    let darker = min(fgL, bgL)
    return (lighter + 0.05) / (darker + 0.05)
}

/// Blends a foreground color (with possible alpha) onto a background using standard alpha compositing.
/// - Returns: Composited sRGB (0..1, no alpha).
private func blendColor(foreground: (r: Double, g: Double, b: Double, a: Double),
                       background: (r: Double, g: Double, b: Double)) -> (r: Double, g: Double, b: Double) {
    let alpha = foreground.a
    let r = (foreground.r * alpha) + (background.r * (1.0 - alpha))
    let g = (foreground.g * alpha) + (background.g * (1.0 - alpha))
    let b = (foreground.b * alpha) + (background.b * (1.0 - alpha))
    return (r, g, b)
}

// MARK: - Color Resolution Helpers

/// Extracts RGBA from a SwiftUI Color by forcing resolution via NSAppearance.
/// For dynamic colors created via macColor(dark:, light:), this ensures the correct variant is used.
private func resolveColor(_ color: Color, appearance: NSAppearance.Name) -> (r: Double, g: Double, b: Double, a: Double) {
    let nsColor = NSColor(color)

    // Convert inside performAsCurrentDrawingAppearance: converting outside it
    // bakes in the test process's appearance and both variants read the same.
    var rgba: (Double, Double, Double, Double) = (0, 0, 0, 0)
    let appearance = NSAppearance(named: appearance)!
    appearance.performAsCurrentDrawingAppearance {
        let sRGB = nsColor.usingColorSpace(.sRGB) ?? nsColor
        rgba = (
            Double(sRGB.redComponent),
            Double(sRGB.greenComponent),
            Double(sRGB.blueComponent),
            Double(sRGB.alphaComponent)
        )
    }
    return rgba
}

// MARK: - Test Suite

struct MacThemeContrastTests {

    // MARK: Text on Background (AA threshold 4.5:1)

    @Test("textPrimary on backgroundBase meets WCAG AA (4.5:1) in dark mode")
    func textPrimaryOnBackgroundBaseDark() {
        let fg = resolveColor(MacTheme.Colors.textPrimary, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .darkAqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Dark: textPrimary on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("textPrimary on backgroundBase meets WCAG AA (4.5:1) in light mode")
    func textPrimaryOnBackgroundBaseLight() {
        let fg = resolveColor(MacTheme.Colors.textPrimary, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .aqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Light: textPrimary on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("textSecondary on backgroundBase meets WCAG AA (4.5:1) in dark mode")
    func textSecondaryOnBackgroundBaseDark() {
        let fg = resolveColor(MacTheme.Colors.textSecondary, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .darkAqua)
        // textSecondary = white.withAlphaComponent(0.88) in dark mode
        let blended = blendColor(foreground: (fg.r, fg.g, fg.b, fg.a), background: (bg.r, bg.g, bg.b))
        let ratio = contrastRatio(foreground: blended, background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Dark: textSecondary on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("textSecondary on backgroundBase meets WCAG AA (4.5:1) in light mode")
    func textSecondaryOnBackgroundBaseLight() {
        let fg = resolveColor(MacTheme.Colors.textSecondary, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .aqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Light: textSecondary on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("textTertiary on backgroundBase meets WCAG AA (4.5:1) in dark mode")
    func textTertiaryOnBackgroundBaseDark() {
        let fg = resolveColor(MacTheme.Colors.textTertiary, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .darkAqua)
        // textTertiary = white.withAlphaComponent(0.68) in dark mode
        let blended = blendColor(foreground: (fg.r, fg.g, fg.b, fg.a), background: (bg.r, bg.g, bg.b))
        let ratio = contrastRatio(foreground: blended, background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Dark: textTertiary on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("textTertiary on backgroundBase meets WCAG AA (4.5:1) in light mode")
    func textTertiaryOnBackgroundBaseLight() {
        let fg = resolveColor(MacTheme.Colors.textTertiary, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .aqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Light: textTertiary on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("sidebarTextPrimary on backgroundGradientStart meets WCAG AA (4.5:1) in dark mode")
    func sidebarTextPrimaryOnGradientStartDark() {
        let fg = resolveColor(MacTheme.Colors.sidebarTextPrimary, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundGradientStart, appearance: .darkAqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Dark: sidebarTextPrimary on backgroundGradientStart = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("sidebarTextPrimary on backgroundGradientStart meets WCAG AA (4.5:1) in light mode")
    func sidebarTextPrimaryOnGradientStartLight() {
        let fg = resolveColor(MacTheme.Colors.sidebarTextPrimary, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundGradientStart, appearance: .aqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Light: sidebarTextPrimary on backgroundGradientStart = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("sidebarTextSecondary on backgroundGradientStart meets WCAG AA (4.5:1) in dark mode")
    func sidebarTextSecondaryOnGradientStartDark() {
        let fg = resolveColor(MacTheme.Colors.sidebarTextSecondary, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundGradientStart, appearance: .darkAqua)
        // sidebarTextSecondary = white.withAlphaComponent(0.85) in dark mode (lines 198-200 of MacTheme.swift)
        let blended = blendColor(foreground: (fg.r, fg.g, fg.b, fg.a), background: (bg.r, bg.g, bg.b))
        let ratio = contrastRatio(foreground: blended, background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Dark: sidebarTextSecondary on backgroundGradientStart = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("sidebarTextSecondary on backgroundGradientStart meets WCAG AA (4.5:1) in light mode")
    func sidebarTextSecondaryOnGradientStartLight() {
        let fg = resolveColor(MacTheme.Colors.sidebarTextSecondary, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundGradientStart, appearance: .aqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Light: sidebarTextSecondary on backgroundGradientStart = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("textPrimary on backgroundElevated meets WCAG AA (4.5:1) in dark mode")
    func textPrimaryOnBackgroundElevatedDark() {
        let fg = resolveColor(MacTheme.Colors.textPrimary, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundElevated, appearance: .darkAqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Dark: textPrimary on backgroundElevated = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("textPrimary on backgroundElevated meets WCAG AA (4.5:1) in light mode")
    func textPrimaryOnBackgroundElevatedLight() {
        let fg = resolveColor(MacTheme.Colors.textPrimary, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundElevated, appearance: .aqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Light: textPrimary on backgroundElevated = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("textSecondary on backgroundElevated meets WCAG AA (4.5:1) in dark mode")
    func textSecondaryOnBackgroundElevatedDark() {
        let fg = resolveColor(MacTheme.Colors.textSecondary, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundElevated, appearance: .darkAqua)
        let blended = blendColor(foreground: (fg.r, fg.g, fg.b, fg.a), background: (bg.r, bg.g, bg.b))
        let ratio = contrastRatio(foreground: blended, background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Dark: textSecondary on backgroundElevated = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("textSecondary on backgroundElevated meets WCAG AA (4.5:1) in light mode")
    func textSecondaryOnBackgroundElevatedLight() {
        let fg = resolveColor(MacTheme.Colors.textSecondary, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundElevated, appearance: .aqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 4.5, "Light: textSecondary on backgroundElevated = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    // MARK: UI/Icon Colors (AA threshold 3:1 for large UI components)

    @Test("success on backgroundBase meets WCAG AA UI (3:1) in dark mode")
    func successOnBackgroundBaseDark() {
        let fg = resolveColor(MacTheme.Colors.success, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .darkAqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 3.0, "Dark: success on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 3:1)")
    }

    @Test("success on backgroundBase meets WCAG AA UI (3:1) in light mode")
    func successOnBackgroundBaseLight() {
        let fg = resolveColor(MacTheme.Colors.success, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .aqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        withKnownIssue("Light-mode status/accent colors are below 3:1 — #361") {
            #expect(ratio >= 3.0, "Light: success on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 3:1)")
        }
    }

    @Test("error on backgroundBase meets WCAG AA UI (3:1) in dark mode")
    func errorOnBackgroundBaseDark() {
        let fg = resolveColor(MacTheme.Colors.error, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .darkAqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 3.0, "Dark: error on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 3:1)")
    }

    @Test("error on backgroundBase meets WCAG AA UI (3:1) in light mode")
    func errorOnBackgroundBaseLight() {
        let fg = resolveColor(MacTheme.Colors.error, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .aqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        withKnownIssue("Light-mode status/accent colors are below 3:1 — #361") {
            #expect(ratio >= 3.0, "Light: error on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 3:1)")
        }
    }

    @Test("sidebarActiveBorder on backgroundBase meets WCAG AA UI (3:1) in dark mode")
    func sidebarActiveBorderOnBackgroundBaseDark() {
        let fg = resolveColor(MacTheme.Colors.sidebarActiveBorder, appearance: .darkAqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .darkAqua)
        let ratio = contrastRatio(foreground: (fg.r, fg.g, fg.b), background: (bg.r, bg.g, bg.b))
        #expect(ratio >= 3.0, "Dark: sidebarActiveBorder on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 3:1)")
    }

    @Test("sidebarActiveBorder on backgroundBase meets WCAG AA UI (3:1) in light mode")
    func sidebarActiveBorderOnBackgroundBaseLight() {
        let fg = resolveColor(MacTheme.Colors.sidebarActiveBorder, appearance: .aqua)
        let bg = resolveColor(MacTheme.Colors.backgroundBase, appearance: .aqua)
        // sidebarActiveBorder in light mode has alpha=0.8 (line 190)
        let blended = blendColor(foreground: (fg.r, fg.g, fg.b, fg.a), background: (bg.r, bg.g, bg.b))
        let ratio = contrastRatio(foreground: blended, background: (bg.r, bg.g, bg.b))
        withKnownIssue("Light-mode status/accent colors are below 3:1 — #361") {
            #expect(ratio >= 3.0, "Light: sidebarActiveBorder on backgroundBase = \(String(format: "%.2f", ratio)):1 (need 3:1)")
        }
    }

    // MARK: Adaptive label colors on glass cards (#334)

    @Test("Adaptive text and label colors resolve differently in light and dark mode",
          arguments: [
              ("textPrimary", MacTheme.Colors.textPrimary),
              ("textSecondary", MacTheme.Colors.textSecondary),
              ("textTertiary", MacTheme.Colors.textTertiary),
              ("labelSecondary", MacTheme.Colors.labelSecondary),
              ("labelTertiary", MacTheme.Colors.labelTertiary),
              ("labelQuaternary", MacTheme.Colors.labelQuaternary),
          ])
    func adaptiveColorsDifferByAppearance(name: String, color: Color) {
        let dark = resolveColor(color, appearance: .darkAqua)
        let light = resolveColor(color, appearance: .aqua)
        #expect(dark.r != light.r || dark.g != light.g || dark.b != light.b,
                "\(name) resolves to the same RGB in light and dark mode")
    }

    @Test("Card label colors meet WCAG AA (4.5:1) on glass in both modes",
          arguments: [
              ("labelSecondary", MacTheme.Colors.labelSecondary),
              ("labelTertiary", MacTheme.Colors.labelTertiary),
          ], [NSAppearance.Name.darkAqua, .aqua])
    func cardLabelOnGlass(token: (name: String, color: Color), appearance: NSAppearance.Name) {
        let ratio = contrastOnGlass(token.color, appearance: appearance)
        #expect(ratio >= 4.5, "\(appearance.rawValue): \(token.name) on glass = \(String(format: "%.2f", ratio)):1 (need 4.5:1)")
    }

    @Test("labelQuaternary meets WCAG AA UI (3:1) on glass in both modes",
          arguments: [NSAppearance.Name.darkAqua, .aqua])
    func labelQuaternaryOnGlass(appearance: NSAppearance.Name) {
        let ratio = contrastOnGlass(MacTheme.Colors.labelQuaternary, appearance: appearance)
        #expect(ratio >= 3.0, "\(appearance.rawValue): labelQuaternary on glass = \(String(format: "%.2f", ratio)):1 (need 3:1)")
    }

    @Test("Dark-mode card labels keep secondary > tertiary > quaternary emphasis")
    func darkLabelHierarchy() {
        let secondary = resolveColor(MacTheme.Colors.labelSecondary, appearance: .darkAqua)
        let tertiary = resolveColor(MacTheme.Colors.labelTertiary, appearance: .darkAqua)
        let quaternary = resolveColor(MacTheme.Colors.labelQuaternary, appearance: .darkAqua)
        #expect(secondary.a > tertiary.a)
        #expect(tertiary.a > quaternary.a)
    }

    @Test("Dark-mode textSecondary/textTertiary brightened from 0.7/0.5 white")
    func darkTextSecondaryBrightened() {
        let textSecondary = resolveColor(MacTheme.Colors.textSecondary, appearance: .darkAqua)
        let textTertiary = resolveColor(MacTheme.Colors.textTertiary, appearance: .darkAqua)
        #expect(textSecondary.a > 0.7)
        #expect(textTertiary.a > 0.5)
    }
}

/// Contrast of `color` over a glass card: crystalBase composited over backgroundBase.
private func contrastOnGlass(_ color: Color, appearance: NSAppearance.Name) -> Double {
    let base = resolveColor(MacTheme.Colors.backgroundBase, appearance: appearance)
    let glass = resolveColor(MacTheme.Colors.crystalBase, appearance: appearance)
    let card = blendColor(foreground: glass, background: (base.r, base.g, base.b))
    let fg = resolveColor(color, appearance: appearance)
    let text = blendColor(foreground: fg, background: card)
    return contrastRatio(foreground: text, background: card)
}
