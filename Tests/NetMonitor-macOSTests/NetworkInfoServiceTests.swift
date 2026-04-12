import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - NetworkInfoError Tests

struct NetworkInfoErrorTests {

    @Test func permissionDeniedDescription() {
        let error = NetworkInfoError.permissionDenied
        #expect(error.errorDescription == "Permission denied to access network information")
    }

    @Test func noActiveInterfaceDescription() {
        let error = NetworkInfoError.noActiveInterface
        #expect(error.errorDescription == "No active network interface found")
    }

    @Test func parsingFailedDescription() {
        let error = NetworkInfoError.parsingFailed("bad SSID format")
        #expect(error.errorDescription == "Failed to parse network information: bad SSID format")
    }
}

// MARK: - ConnectionInfo Tests

struct ConnectionInfoTests {

    @Test func wifiConnectionInitialization() {
        let info = ConnectionInfo(
            connectionType: .wifi,
            ssid: "MyNetwork",
            bssid: "aa:bb:cc:dd:ee:ff",
            signalStrength: -65,
            channel: 6,
            linkSpeed: 300,
            interfaceName: "en0"
        )
        #expect(info.connectionType == .wifi)
        #expect(info.ssid == "MyNetwork")
        #expect(info.bssid == "aa:bb:cc:dd:ee:ff")
        #expect(info.signalStrength == -65)
        #expect(info.channel == 6)
        #expect(info.linkSpeed == 300)
        #expect(info.interfaceName == "en0")
    }

    @Test func ethernetConnectionInitialization() {
        let info = ConnectionInfo(
            connectionType: .ethernet,
            ssid: nil,
            bssid: nil,
            signalStrength: nil,
            channel: nil,
            linkSpeed: 1000,
            interfaceName: "en1"
        )
        #expect(info.connectionType == .ethernet)
        #expect(info.ssid == nil)
        #expect(info.bssid == nil)
        #expect(info.signalStrength == nil)
        #expect(info.channel == nil)
        #expect(info.linkSpeed == 1000)
        #expect(info.interfaceName == "en1")
    }

    @Test func minimalConnectionInitialization() {
        let info = ConnectionInfo(
            connectionType: .wifi,
            ssid: nil,
            bssid: nil,
            signalStrength: nil,
            channel: nil,
            linkSpeed: nil,
            interfaceName: "en0"
        )
        #expect(info.connectionType == .wifi)
        #expect(info.ssid == nil)
        #expect(info.linkSpeed == nil)
    }
}
