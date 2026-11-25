import Testing
import Foundation
@testable import NetMonitor_iOS

// MARK: - PingIntent Tests

/// Why the intent-instantiation tests are disabled.
private let instantiationCrash: Comment =
    "AppIntents instantiation crashes on Xcode 26 beta — framework requires runtime context unavailable in tests"

@MainActor
struct PingIntentTests {

    @Test("title is set correctly")
    func titleIsCorrect() {
        #expect(PingIntent.title == "Ping a Host")
    }

    @Test("default count is 4", .disabled(instantiationCrash))
    func defaultCountIs4() {
        let intent = PingIntent()
        #expect(intent.count == 4)
    }

    @Test("host defaults to empty string", .disabled(instantiationCrash))
    func hostDefaultsToEmpty() {
        let intent = PingIntent()
        #expect(intent.host.isEmpty)
    }

    @Test("host can be set", .disabled(instantiationCrash))
    func hostCanBeSet() {
        var intent = PingIntent()
        intent.host = "8.8.8.8"
        #expect(intent.host == "8.8.8.8")
    }

    @Test("count can be set within range", .disabled(instantiationCrash))
    func countCanBeSet() {
        var intent = PingIntent()
        intent.count = 10
        #expect(intent.count == 10)
    }
}

// MARK: - ScanNetworkIntent Tests

@MainActor
struct ScanNetworkIntentTests {

    @Test("title is set correctly")
    func titleIsCorrect() {
        #expect(ScanNetworkIntent.title == "Scan My Network")
    }

    @Test("intent can be created with no parameters", .disabled(instantiationCrash))
    func intentCreation() {
        let intent = ScanNetworkIntent()
        _ = intent  // Just verify it creates without error
        #expect(Bool(true))
    }
}

// MARK: - SpeedTestIntent Tests

@MainActor
struct SpeedTestIntentTests {

    @Test("title is set correctly")
    func titleIsCorrect() {
        #expect(SpeedTestIntent.title == "Run Speed Test")
    }

    @Test("intent can be created with no parameters", .disabled(instantiationCrash))
    func intentCreation() {
        let intent = SpeedTestIntent()
        _ = intent
        #expect(Bool(true))
    }
}

// MARK: - NetworkStatusIntent Tests

@MainActor
struct NetworkStatusIntentTests {

    @Test("title is set correctly")
    func titleIsCorrect() {
        #expect(NetworkStatusIntent.title == "Network Status")
    }

    @Test("intent can be created with no parameters", .disabled(instantiationCrash))
    func intentCreation() {
        let intent = NetworkStatusIntent()
        _ = intent
        #expect(Bool(true))
    }
}

// MARK: - NetMonitorShortcuts Tests

@MainActor
struct NetMonitorShortcutsTests {

    @Test("shortcuts provider includes all expected entries")
    func shortcutMembership() {
        let shortcuts = NetMonitorShortcuts.appShortcuts
        let shortcutIDs = NetMonitorShortcuts.shortcutIDs

        #expect(shortcuts.count == shortcutIDs.count)
        #expect(shortcutIDs.contains(.ping))
        #expect(shortcutIDs.contains(.scanNetwork))
        #expect(shortcutIDs.contains(.speedTest))
        #expect(shortcutIDs.contains(.networkStatus))
        #expect(shortcutIDs.contains(.saveWiFiReading))
        #expect(shortcutIDs.contains(.ask))
    }
}
