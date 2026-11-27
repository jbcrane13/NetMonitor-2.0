import Foundation
import NetMonitorCore

// Where the shared connection service keeps the paired Mac and its marks.
extension MacConnectionService {
    /// The Keychain, or memory for `--uitesting` launches of Debug builds.
    static func defaultMacStore() -> PairedMacStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting") {
            return PairedMacStore(backing: UITestFakeMacPairing.store)
        }
        #endif
        return PairedMacStore(backing: CompanionKeychain(service: "com.netmonitor.companion.mac", accessibility: .whenUnlocked))
    }

    static func defaultDefaults() -> UserDefaults {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitesting"),
           let suite = UserDefaults(suiteName: UITestFakeMacPairing.defaultsSuite) {
            return suite
        }
        #endif
        return .standard
    }
}
