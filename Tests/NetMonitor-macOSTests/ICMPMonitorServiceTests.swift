import Foundation
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - ICMPMonitorService Tests

struct ICMPMonitorServiceProtocolTests {

    // INTEGRATION GAP: ICMPMonitorService uses NetMonitorCore's PingService which
    // requires ICMP socket entitlement or raw socket privilege. The actual ping
    // cannot be tested in unit tests without network access and entitlements.
    // Tests below verify the protocol guard logic and error paths.

    @Test("check throws for non-ICMP protocol")
    func checkThrowsForNonICMPProtocol() async {
        let service = ICMPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "8.8.8.8",
            port: nil,
            targetProtocol: .http,
            timeout: 5.0
        )

        await #expect(throws: NetworkMonitorError.self) {
            _ = try await service.check(request: request)
        }
    }

    @Test("check throws for TCP protocol")
    func checkThrowsForTCPProtocol() async {
        let service = ICMPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "8.8.8.8",
            port: 80,
            targetProtocol: .tcp,
            timeout: 5.0
        )

        await #expect(throws: NetworkMonitorError.self) {
            _ = try await service.check(request: request)
        }
    }

    @Test("check throws for HTTPS protocol")
    func checkThrowsForHTTPSProtocol() async {
        let service = ICMPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "google.com",
            port: nil,
            targetProtocol: .https,
            timeout: 5.0
        )

        await #expect(throws: NetworkMonitorError.self) {
            _ = try await service.check(request: request)
        }
    }

    @Test("check error message mentions ICMP requirement")
    func checkErrorMentionsICMP() async {
        let service = ICMPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "test.local",
            port: nil,
            targetProtocol: .tcp,
            timeout: 5.0
        )

        do {
            _ = try await service.check(request: request)
            Issue.record("Expected NetworkMonitorError")
        } catch let error as NetworkMonitorError {
            let description = error.description
            #expect(description.contains("ICMP"), "Error should mention ICMP protocol requirement")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - ICMPMonitorService Request/Result Value Tests

struct ICMPMonitorServiceValueTypeTests {

    @Test("TargetCheckRequest stores ICMP protocol correctly")
    func requestStoresICMPProtocol() {
        let id = UUID()
        let request = TargetCheckRequest(
            id: id,
            host: "192.168.1.1",
            port: nil,
            targetProtocol: .icmp,
            timeout: 3.0
        )

        #expect(request.id == id)
        #expect(request.host == "192.168.1.1")
        #expect(request.port == nil)
        #expect(request.targetProtocol == .icmp)
        #expect(request.timeout == 3.0)
    }

    @Test("MeasurementResult captures reachable state")
    func measurementResultReachable() {
        let id = UUID()
        let result = MeasurementResult(
            targetID: id,
            timestamp: Date(),
            latency: 12.5,
            isReachable: true,
            errorMessage: nil
        )

        #expect(result.targetID == id)
        #expect(result.latency == 12.5)
        #expect(result.isReachable == true)
        #expect(result.errorMessage == nil)
    }

    @Test("MeasurementResult captures unreachable state with error")
    func measurementResultUnreachable() {
        let id = UUID()
        let result = MeasurementResult(
            targetID: id,
            timestamp: Date(),
            latency: nil,
            isReachable: false,
            errorMessage: "Host unreachable (timeout)"
        )

        #expect(result.latency == nil)
        #expect(result.isReachable == false)
        #expect(result.errorMessage == "Host unreachable (timeout)")
    }
}
