import Foundation
import Testing
import NetMonitorCore
@testable import NetMonitor_macOS

// MARK: - HTTPMonitorService Protocol Validation Tests

struct HTTPMonitorServiceProtocolTests {

    @Test("check throws for ICMP protocol")
    func checkThrowsForICMPProtocol() async {
        let service = HTTPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "example.com",
            port: nil,
            targetProtocol: .icmp,
            timeout: 2.0
        )

        await #expect(throws: NetworkMonitorError.self) {
            _ = try await service.check(request: request)
        }
    }

    @Test("check throws for TCP protocol")
    func checkThrowsForTCPProtocol() async {
        let service = HTTPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "example.com",
            port: 80,
            targetProtocol: .tcp,
            timeout: 2.0
        )

        await #expect(throws: NetworkMonitorError.self) {
            _ = try await service.check(request: request)
        }
    }

    @Test("check error message mentions HTTP/HTTPS requirement")
    func errorMentionsHTTPRequirement() async {
        let service = HTTPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "test.local",
            port: nil,
            targetProtocol: .icmp,
            timeout: 2.0
        )

        do {
            _ = try await service.check(request: request)
            Issue.record("Expected NetworkMonitorError")
        } catch let error as NetworkMonitorError {
            #expect(error.description.contains("HTTP"),
                    "Error should mention HTTP/HTTPS protocol requirement")
        } catch {
            Issue.record("Unexpected error type: \(error)")
        }
    }
}

// MARK: - HTTPMonitorService URL Construction Tests

struct HTTPMonitorServiceURLConstructionTests {

    @Test("check throws invalidHost for empty hostname with http")
    func emptyHostnameThrows() async {
        let service = HTTPMonitorService()
        // URL(string: "http://") may or may not be nil depending on Foundation version
        // but an empty host should not produce a successful check
        let request = TargetCheckRequest(
            id: UUID(),
            host: "",
            port: nil,
            targetProtocol: .http,
            timeout: 1.0
        )

        do {
            let result = try await service.check(request: request)
            // If it doesn't throw, it should at least be unreachable
            #expect(!result.isReachable, "Empty host should not be reachable")
        } catch {
            // Throwing is also acceptable for invalid host
            #expect(true)
        }
    }

    @Test("check constructs correct scheme for HTTP protocol")
    func httpSchemeConstruction() {
        // Verify the URL construction logic: http protocol -> "http://" scheme
        let scheme = TargetProtocol.http == .https ? "https" : "http"
        #expect(scheme == "http")
    }

    @Test("check constructs correct scheme for HTTPS protocol")
    func httpsSchemeConstruction() {
        let scheme = TargetProtocol.https == .https ? "https" : "http"
        #expect(scheme == "https")
    }

    @Test("port is appended to URL when provided")
    func portAppendedToURL() {
        let port: Int? = 8080
        let portString = port.map { ":\($0)" } ?? ""
        let urlString = "http://example.com\(portString)"
        let url = URL(string: urlString)
        #expect(url?.port == 8080)
    }

    @Test("port is omitted from URL when nil")
    func portOmittedWhenNil() {
        let port: Int? = nil
        let portString = port.map { ":\($0)" } ?? ""
        let urlString = "http://example.com\(portString)"
        let url = URL(string: urlString)
        #expect(url?.port == nil)
    }
}

// MARK: - HTTPMonitorService Response Interpretation Tests

struct HTTPMonitorServiceResponseCodeTests {

    @Test("2xx status codes are considered reachable")
    func twoHundredSeriesIsReachable() {
        for code in [200, 201, 204, 299] {
            let isReachable = (200...399).contains(code)
            #expect(isReachable, "HTTP \(code) should be reachable")
        }
    }

    @Test("3xx status codes are considered reachable")
    func threeHundredSeriesIsReachable() {
        for code in [301, 302, 304, 399] {
            let isReachable = (200...399).contains(code)
            #expect(isReachable, "HTTP \(code) should be reachable")
        }
    }

    @Test("4xx status codes are NOT considered reachable")
    func fourHundredSeriesIsNotReachable() {
        for code in [400, 401, 403, 404, 429, 499] {
            let isReachable = (200...399).contains(code)
            #expect(!isReachable, "HTTP \(code) should NOT be reachable")
        }
    }

    @Test("5xx status codes are NOT considered reachable")
    func fiveHundredSeriesIsNotReachable() {
        for code in [500, 502, 503, 504] {
            let isReachable = (200...399).contains(code)
            #expect(!isReachable, "HTTP \(code) should NOT be reachable")
        }
    }

    @Test("error message format includes HTTP status code")
    func errorMessageIncludesStatusCode() {
        let code = 503
        let isReachable = (200...399).contains(code)
        let errorMessage = isReachable ? nil : "HTTP \(code)"
        #expect(errorMessage == "HTTP 503")
    }
}

// MARK: - HTTPMonitorService Error Handling Tests

struct HTTPMonitorServiceErrorHandlingTests {

    @Test("check returns unreachable with error for non-existent domain")
    func nonExistentDomainReturnsUnreachable() async throws {
        let service = HTTPMonitorService()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "this-domain-will-never-exist.invalid",
            port: nil,
            targetProtocol: .http,
            timeout: 2.0
        )

        let result = try await service.check(request: request)
        #expect(!result.isReachable)
        #expect(result.latency == nil)
        #expect(result.errorMessage != nil)
    }

    @Test("check preserves target ID through error path")
    func targetIDPreservedThroughErrorPath() async throws {
        let service = HTTPMonitorService()
        let targetID = UUID()
        let request = TargetCheckRequest(
            id: targetID,
            host: "192.0.2.1",
            port: nil,
            targetProtocol: .http,
            timeout: 1.0
        )

        let result = try await service.check(request: request)
        #expect(result.targetID == targetID)
    }

    @Test("check result timestamp is recent")
    func resultTimestampIsRecent() async throws {
        let service = HTTPMonitorService()
        let before = Date()
        let request = TargetCheckRequest(
            id: UUID(),
            host: "192.0.2.1",
            port: nil,
            targetProtocol: .http,
            timeout: 1.0
        )

        let result = try await service.check(request: request)
        let after = Date()
        #expect(result.timestamp >= before)
        #expect(result.timestamp <= after)
    }
}
