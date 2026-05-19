import SwiftUI

// MARK: - Liquid Glass Helpers
//
// `.glassEffect(_:in:)` is gated to iOS 26.0+ in the SwiftUI SDK (Liquid Glass design,
// WWDC 2025). The app deploys to iOS 18.0, so every site needs an availability check.
// These helpers centralize that gate and fall back to `.ultraThinMaterial` on iOS 18–25.

/// A shape filled with the platform's "glass" effect — for use as a layer
/// inside a `ZStack` background composition.
///
/// On iOS 26+ this is rendered via `.glassEffect()` (Liquid Glass).
/// On iOS 18–25 it falls back to `shape.fill(.ultraThinMaterial)`.
@MainActor
struct LiquidGlassFill<S: Shape>: View {
    let shape: S
    var tint: Color?

    init(_ shape: S, tint: Color? = nil) {
        self.shape = shape
        self.tint = tint
    }

    @ViewBuilder
    var body: some View {
        if #available(iOS 26.0, *) {
            shape
                .fill(.clear)
                .glassEffect(.regular.tint(tint), in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

extension View {
    /// Liquid Glass background for the view, clipped to `shape`.
    /// Drop-in replacement for `.background(shape.fill(.ultraThinMaterial))`.
    @ViewBuilder
    func liquidGlassBackground(in shape: some Shape, tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint), in: shape)
        } else {
            self.background(shape.fill(.ultraThinMaterial))
        }
    }

    /// Liquid Glass background with the SwiftUI default glass shape.
    /// Drop-in replacement for `.background(.ultraThinMaterial)`.
    @ViewBuilder
    func liquidGlassBackground(tint: Color? = nil) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(tint))
        } else {
            self.background(.ultraThinMaterial)
        }
    }
}
