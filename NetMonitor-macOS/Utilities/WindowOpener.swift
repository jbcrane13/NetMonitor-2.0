import SwiftUI

/// Bridges SwiftUI's `OpenWindowAction` so non-view code (menu bar popover)
/// can reopen the main window after the user has closed it.
///
/// Usage:
/// - In the WindowGroup content: `.captureOpenWindow()`
/// - From anywhere: `WindowOpener.shared.openMainWindow()`
@MainActor
final class WindowOpener {
    static let shared = WindowOpener()
    fileprivate var openWindow: OpenWindowAction?
    private init() {}

    /// Opens the main window, creating it if it was closed.
    func openMainWindow() {
        if let window = NSApp.windows.first(where: { $0.isVisible && $0.canBecomeMain }) {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else if let openWindow {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        } else {
            // Last resort — activate and hope SwiftUI reopens the window
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - View Modifier

/// Captures the `openWindow` environment action into `WindowOpener.shared`.
/// Attach to any view inside the main WindowGroup.
private struct CaptureOpenWindowModifier: ViewModifier {
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear {
                WindowOpener.shared.openWindow = openWindow
            }
    }
}

extension View {
    func captureOpenWindow() -> some View {
        modifier(CaptureOpenWindowModifier())
    }
}
