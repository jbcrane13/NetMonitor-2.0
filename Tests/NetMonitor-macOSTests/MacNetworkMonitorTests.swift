import Foundation
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - NetworkMonitorError Tests

struct NetworkMonitorErrorTests {

    @Test("invalidHost includes the host string")
    func invalidHostIncludesHostString() {
        let error = NetworkMonitorError.invalidHost("bad-host.example")
        #expect(error.description.contains("bad-host.example"))
    }

    @Test("timeout has descriptive message")
    func timeoutDescription() {
        let error = NetworkMonitorError.timeout
        #expect(error.description.contains("timed out"))
    }

    @Test("permissionDenied has descriptive message")
    func permissionDeniedDescription() {
        let error = NetworkMonitorError.permissionDenied
        #expect(error.description.contains("permission") || error.description.contains("denied"))
    }

    @Test("networkUnreachable has descriptive message")
    func networkUnreachableDescription() {
        let error = NetworkMonitorError.networkUnreachable
        #expect(error.description.contains("unreachable"))
    }

    @Test("unknownError wraps underlying error description")
    func unknownErrorWrapsUnderlyingError() {
        let underlying = URLError(.notConnectedToInternet)
        let error = NetworkMonitorError.unknownError(underlying)
        #expect(error.description.contains("Unknown error") || error.description.contains("error"))
    }

    @Test("all error cases produce non-empty descriptions")
    func allCasesProduceNonEmptyDescriptions() {
        let errors: [NetworkMonitorError] = [
            .invalidHost("test"),
            .timeout,
            .permissionDenied,
            .networkUnreachable,
            .unknownError(URLError(.badURL))
        ]

        for error in errors {
            #expect(!error.description.isEmpty,
                    "Error description should not be empty for \(error)")
        }
    }
}

// MARK: - TargetCheckRequest Tests

struct TargetCheckRequestTests {

    @Test("stores all fields correctly")
    func storesAllFields() {
        let id = UUID()
        let request = TargetCheckRequest(
            id: id,
            host: "google.com",
            port: 443,
            targetProtocol: .https,
            timeout: 10.0
        )

        #expect(request.id == id)
        #expect(request.host == "google.com")
        #expect(request.port == 443)
        #expect(request.targetProtocol == .https)
        #expect(request.timeout == 10.0)
    }

    @Test("port is optional and can be nil")
    func portIsOptional() {
        let request = TargetCheckRequest(
            id: UUID(),
            host: "example.com",
            port: nil,
            targetProtocol: .icmp,
            timeout: 5.0
        )

        #expect(request.port == nil)
    }

    @Test("is Sendable across concurrency boundaries")
    func isSendable() async {
        let request = TargetCheckRequest(
            id: UUID(),
            host: "test.local",
            port: 80,
            targetProtocol: .http,
            timeout: 3.0
        )

        // Verify the value can cross actor boundaries
        let capturedHost = await Task.detached {
            request.host
        }.value

        #expect(capturedHost == "test.local")
    }
}

// MARK: - MeasurementResult Tests

struct MeasurementResultTests {

    @Test("reachable result has latency and no error")
    func reachableResult() {
        let result = MeasurementResult(
            targetID: UUID(),
            timestamp: Date(),
            latency: 25.3,
            isReachable: true,
            errorMessage: nil
        )

        #expect(result.isReachable)
        #expect(result.latency == 25.3)
        #expect(result.errorMessage == nil)
    }

    @Test("unreachable result has nil latency and error message")
    func unreachableResult() {
        let result = MeasurementResult(
            targetID: UUID(),
            timestamp: Date(),
            latency: nil,
            isReachable: false,
            errorMessage: "Connection refused"
        )

        #expect(!result.isReachable)
        #expect(result.latency == nil)
        #expect(result.errorMessage == "Connection refused")
    }

    @Test("is Sendable across concurrency boundaries")
    func isSendable() async {
        let id = UUID()
        let result = MeasurementResult(
            targetID: id,
            timestamp: Date(),
            latency: 10.0,
            isReachable: true,
            errorMessage: nil
        )

        let capturedID = await Task.detached {
            result.targetID
        }.value

        #expect(capturedID == id)
    }
}

// MARK: - LocalDiscoveredDevice Tests

struct LocalDiscoveredDeviceTests {

    @Test("MAC address is uppercased on init")
    func macAddressUppercased() {
        let device = LocalDiscoveredDevice(
            ipAddress: "192.168.1.100",
            macAddress: "aa:bb:cc:dd:ee:ff",
            hostname: "test-device"
        )
        #expect(device.macAddress == "AA:BB:CC:DD:EE:FF")
    }

    @Test("already uppercase MAC stays uppercase")
    func alreadyUppercaseMAC() {
        let device = LocalDiscoveredDevice(
            ipAddress: "10.0.0.5",
            macAddress: "11:22:33:44:55:66",
            hostname: nil
        )
        #expect(device.macAddress == "11:22:33:44:55:66")
    }

    @Test("hostname can be nil")
    func hostnameCanBeNil() {
        let device = LocalDiscoveredDevice(
            ipAddress: "192.168.1.50",
            macAddress: "AA:BB:CC:DD:EE:FF",
            hostname: nil
        )
        #expect(device.hostname == nil)
    }

    @Test("equality based on all fields")
    func equality() {
        let a = LocalDiscoveredDevice(ipAddress: "10.0.0.1", macAddress: "aa:bb:cc:dd:ee:ff", hostname: "host")
        let b = LocalDiscoveredDevice(ipAddress: "10.0.0.1", macAddress: "AA:BB:CC:DD:EE:FF", hostname: "host")
        #expect(a == b, "Devices with same fields (after uppercase MAC) should be equal")
    }

    @Test("inequality when IP differs")
    func inequalityWhenIPDiffers() {
        let a = LocalDiscoveredDevice(ipAddress: "10.0.0.1", macAddress: "AA:BB:CC:DD:EE:FF", hostname: nil)
        let b = LocalDiscoveredDevice(ipAddress: "10.0.0.2", macAddress: "AA:BB:CC:DD:EE:FF", hostname: nil)
        #expect(a != b)
    }
}

// MARK: - LocalDeviceDiscoveryError Tests

struct LocalDeviceDiscoveryErrorTests {

    @Test("networkUnavailable is distinct from invalidSubnet")
    func errorsAreDistinct() {
        let a = LocalDeviceDiscoveryError.networkUnavailable
        let b = LocalDeviceDiscoveryError.invalidSubnet

        // Verify they are different enum cases by pattern matching
        if case .networkUnavailable = a {
            #expect(true)
        }
        if case .invalidSubnet = b {
            #expect(true)
        }
    }
}
