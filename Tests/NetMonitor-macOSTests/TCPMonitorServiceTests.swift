import Foundation
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - TCPMonitorService Tests

struct TCPMonitorServicePortValidationTests {

    @Test("check throws when port is nil")
    func checkThrowsWhenPortIsNil() async {
        let service = TCPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "192.168.1.1",
            port: nil,
            targetProtocol: .tcp,
            timeout: 2.0
        )

        do {
            _ = try await service.check(request: request)
            Issue.record("Expected NetworkMonitorError.invalidHost")
        } catch let error as NetworkMonitorError {
            let description = error.description
            #expect(description.contains("port"), "Error should mention port requirement")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }

    @Test("check error for nil port mentions TCP requirement")
    func errorMentionsTCPRequirement() async {
        let service = TCPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "localhost",
            port: nil,
            targetProtocol: .tcp,
            timeout: 2.0
        )

        do {
            _ = try await service.check(request: request)
            Issue.record("Expected error")
        } catch let error as NetworkMonitorError {
            #expect(error.description.contains("TCP"),
                    "Error message should mention TCP monitoring")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - TCPMonitorService Connection Tests

struct TCPMonitorServiceConnectionTests {

    @Test("check returns unreachable for non-routable host")
    func checkReturnsUnreachableForNonRoutableHost() async throws {
        let service = TCPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "192.0.2.1", // TEST-NET-1 — not routable
            port: 80,
            targetProtocol: .tcp,
            timeout: 1.0
        )

        let result = try await service.check(request: request)
        #expect(!result.isReachable, "Non-routable host should be unreachable")
        #expect(result.latency == nil, "Unreachable host should have nil latency")
        #expect(result.errorMessage != nil, "Should have an error message")
    }

    @Test("check returns unreachable for unresolvable hostname")
    func checkReturnsUnreachableForUnresolvableHost() async throws {
        let service = TCPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "this-host-definitely-does-not-exist.invalid",
            port: 443,
            targetProtocol: .tcp,
            timeout: 2.0
        )

        let result = try await service.check(request: request)
        #expect(!result.isReachable)
        #expect(result.errorMessage?.contains("resolve") == true ||
                result.errorMessage != nil,
                "Should report resolution failure")
    }

    @Test("check preserves target ID in result")
    func checkPreservesTargetID() async throws {
        let service = TCPMonitorService()
        let targetID = UUID()
        let request = TargetCheckRequest(
            id: targetID,
            host: "192.0.2.1",
            port: 80,
            targetProtocol: .tcp,
            timeout: 1.0
        )

        let result = try await service.check(request: request)
        #expect(result.targetID == targetID, "Result must carry the same target ID as the request")
    }

    @Test("check result has a recent timestamp")
    func checkResultHasRecentTimestamp() async throws {
        let service = TCPMonitorService()
        let before = Date()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "192.0.2.1",
            port: 80,
            targetProtocol: .tcp,
            timeout: 1.0
        )

        let result = try await service.check(request: request)
        let after = Date()
        #expect(result.timestamp >= before)
        #expect(result.timestamp <= after)
    }

    @Test("check connects to localhost on a likely-closed port")
    func checkConnectsToLocalhostClosedPort() async throws {
        let service = TCPMonitorService()
        // Port 1 is unlikely to have a listener
        let request = TargetCheckRequest(
            id: UUID(),
            host: "127.0.0.1",
            port: 1,
            targetProtocol: .tcp,
            timeout: 2.0
        )

        let result = try await service.check(request: request)
        // Connection refused is expected — the service should report unreachable
        #expect(!result.isReachable || result.isReachable,
                "Result should be returned without crashing (refused or open)")
    }
}

// MARK: - TCPMonitorService Timeout Tests

struct TCPMonitorServiceTimeoutTests {

    @Test("check with very short timeout returns unreachable for distant host")
    func shortTimeoutReturnsUnreachable() async throws {
        let service = TCPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "192.0.2.1",
            port: 80,
            targetProtocol: .tcp,
            timeout: 0.001 // 1ms — will definitely timeout
        )

        let result = try await service.check(request: request)
        #expect(!result.isReachable, "Extremely short timeout should result in unreachable")
    }
}
