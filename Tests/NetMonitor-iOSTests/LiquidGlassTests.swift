import SwiftUI
import Testing
@testable import NetMonitor_iOS

// MARK: - LiquidGlass

@MainActor
struct LiquidGlassFillTests {
    /// Smoke test: the view compiles and is constructible with the default tint.
    @Test func defaultConstruction() {
        let view = LiquidGlassFill(RoundedRectangle(cornerRadius: 20))
        #expect(view.tint == nil)
    }

    /// Smoke test: explicit tint is retained.
    @Test func tintIsRetained() {
        let view = LiquidGlassFill(Circle(), tint: .blue)
        #expect(view.tint == Color.blue)
    }

    /// Smoke test: works with multiple shape types (generic over `Shape`).
    @Test func acceptsVariousShapes() {
        _ = LiquidGlassFill(RoundedRectangle(cornerRadius: 12))
        _ = LiquidGlassFill(Circle())
        _ = LiquidGlassFill(Capsule())
        _ = LiquidGlassFill(Rectangle())
    }
}

@MainActor
struct LiquidGlassBackgroundModifierTests {
    /// The `.liquidGlassBackground(in:tint:)` modifier returns a view.
    @Test func shapeModifierReturnsView() {
        let modified = Text("hi").liquidGlassBackground(in: RoundedRectangle(cornerRadius: 8))
        _ = AnyView(modified)
    }

    /// The `.liquidGlassBackground(tint:)` modifier (default shape) returns a view.
    @Test func defaultShapeModifierReturnsView() {
        let modified = Text("hi").liquidGlassBackground()
        _ = AnyView(modified)
    }

    /// Tint parameter compiles for both overloads.
    @Test func tintCompiles() {
        _ = Text("hi").liquidGlassBackground(in: Capsule(), tint: .red)
        _ = Text("hi").liquidGlassBackground(tint: .green)
    }
}
