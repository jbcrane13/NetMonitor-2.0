import Testing
import Foundation
@testable import NetMonitor_iOS

// MARK: - PingIntent Tests

@Suite("PingIntent")
@MainActor
struct PingIntentTests {

    @Test("title is set correctly")
    func titleIsCorrect() {
        #expect(PingIntent.title == "Ping a Host")
    }

    @Test("default count is 4")
    func defaultCountIs4() {
        let intent = PingIntent()
        #expect(intent.count == 4)
    }

    @Test("host defaults to empty string")
    func hostDefaultsToEmpty() {
        let intent = PingIntent()
        #expect(intent.host == "")
    }

    @Test("host can be set")
    func hostCanBeSet() {
        var intent = PingIntent()
        intent.host = "8.8.8.8"
        #expect(intent.host == "8.8.8.8")
    }

    @Test("count can be set within range")
    func countCanBeSet() {
        var intent = PingIntent()
        intent.count = 10
        #expect(intent.count == 10)
    }
}

// MARK: - ScanNetworkIntent Tests

@Suite("ScanNetworkIntent")
@MainActor
struct ScanNetworkIntentTests {

    @Test("title is set correctly")
    func titleIsCorrect() {
        #expect(ScanNetworkIntent.title == "Scan My Network")
    }

    @Test("intent can be created with no parameters")
    func intentCreation() {
        let intent = ScanNetworkIntent()
        _ = intent  // Just verify it creates without error
        #expect(Bool(true))
    }
}

// MARK: - SpeedTestIntent Tests

@Suite("SpeedTestIntent")
@MainActor
struct SpeedTestIntentTests {

    @Test("title is set correctly")
    func titleIsCorrect() {
        #expect(SpeedTestIntent.title == "Run Speed Test")
    }

    @Test("intent can be created with no parameters")
    func intentCreation() {
        let intent = SpeedTestIntent()
        _ = intent
        #expect(Bool(true))
    }
}

// MARK: - NetworkStatusIntent Tests

@Suite("NetworkStatusIntent")
@MainActor
struct NetworkStatusIntentTests {

    @Test("title is set correctly")
    func titleIsCorrect() {
        #expect(NetworkStatusIntent.title == "Network Status")
    }

    @Test("intent can be created with no parameters")
    func intentCreation() {
        let intent = NetworkStatusIntent()
        _ = intent
        #expect(Bool(true))
    }
}

// MARK: - NetMonitorShortcuts Tests

@Suite("NetMonitorShortcuts")
@MainActor
struct NetMonitorShortcutsTests {

    @Test("shortcuts provider has 4 shortcuts")
    func shortcutCount() {
        let shortcuts = NetMonitorShortcuts.appShortcuts
        #expect(shortcuts.count == 4)
    }
}
