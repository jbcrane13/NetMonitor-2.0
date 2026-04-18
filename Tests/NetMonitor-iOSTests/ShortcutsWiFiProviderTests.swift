import Foundation
import Testing
@testable import NetMonitor_iOS

struct ShortcutsWiFiProviderTests {

    /// Regression guard for the 3s → 10s timeout bump.
    /// Slow devices frequently exceed a 3s Shortcuts round-trip; the shorter
    /// timeout produced the user-visible "-100 dBm" field incident tracked
    /// on 2026-04-16. The setup-view copy and the provider constant must
    /// stay synchronized at 10s.
    @Test func defaultTimeoutIsTenSeconds() {
        #expect(ShortcutsWiFiProvider.defaultTimeout == 10.0)
    }
}
