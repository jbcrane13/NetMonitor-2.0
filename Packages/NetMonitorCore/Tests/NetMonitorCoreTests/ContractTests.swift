import Foundation
import Testing
@testable import NetMonitorCore

/// All URL contract tests live in one `.serialized` suite to prevent shared
/// `MockURLProtocol.requestHandler` from being overwritten by concurrent tests.
@Suite("Contract Tests", .serialized)
struct ContractTests {

    // MARK: - WorldPingService

    @Suite("WorldPingService")
    struct WorldPingServiceContractTests {

        // Resets shared handler before each test runs to prevent bleed-in from
        // a previous test if the suite is ever moved to parallel execution.
        init() { MockURLProtocol.requestHandler = nil }

        @Test("Full ping flow: real decoder parses submit response and maps 5 nodes")
        func fullPingFlowDecodesAllNodes() async throws {
            let submitJSON = try MockURLProtocol.loadFixture(named: "globalping-submit-success.json")
            let resultsJSON = try MockURLProtocol.loadFixture(named: "globalping-result-complete.json")
            let session = MockURLProtocol.makeSession { request in
                let data = request.httpMethod == "POST" ? Data(submitJSON.utf8) : Data(resultsJSON.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let service = WorldPingService(session: session)
            var results: [WorldPingLocationResult] = []
            for await result in await service.ping(host: "google.com", maxNodes: 5) {
                results.append(result)
            }

            #expect(results.count == 5, "All 5 nodes from fixture should be returned")
            #expect(results.allSatisfy { $0.isSuccess }, "All nodes in complete fixture should succeed")
        }

        @Test("Latency value from timings.total is used as latencyMs")
        func latencyFromTimingsTotal() async throws {
            let submitJSON = try MockURLProtocol.loadFixture(named: "globalping-submit-success.json")
            let resultsJSON = try MockURLProtocol.loadFixture(named: "globalping-result-complete.json")
            let session = MockURLProtocol.makeSession { request in
                let data = request.httpMethod == "POST" ? Data(submitJSON.utf8) : Data(resultsJSON.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let service = WorldPingService(session: session)
            var results: [WorldPingLocationResult] = []
            for await result in await service.ping(host: "google.com", maxNodes: 5) {
                results.append(result)
            }

            // Frankfurt node in fixture: timings.total = 32.0 ms
            let frankfurt = results.first(where: { $0.city == "Frankfurt" })
            #expect(frankfurt != nil, "Frankfurt node should be present")
            if let ms = frankfurt?.latencyMs {
                #expect(abs(ms - 32.0) < 0.1, "timings.total=32.0 should map to 32ms, got \(ms)ms")
            }
        }

        @Test("Node metadata (city, continent name) is mapped from probe fields")
        func nodeMetadataIsPopulated() async throws {
            let submitJSON = try MockURLProtocol.loadFixture(named: "globalping-submit-success.json")
            let resultsJSON = try MockURLProtocol.loadFixture(named: "globalping-result-complete.json")
            let session = MockURLProtocol.makeSession { request in
                let data = request.httpMethod == "POST" ? Data(submitJSON.utf8) : Data(resultsJSON.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let service = WorldPingService(session: session)
            var results: [WorldPingLocationResult] = []
            for await result in await service.ping(host: "8.8.8.8", maxNodes: 5) {
                results.append(result)
            }

            let cityNames = results.map { $0.city }
            #expect(cityNames.contains("Frankfurt"))
            #expect(cityNames.contains("Ashburn"))
            #expect(cityNames.contains("Tokyo"))
            // Globalping uses continent codes; service maps them to continent display names
            let countries = results.map { $0.country }
            #expect(countries.contains("Europe"))
            #expect(countries.contains("North America"))
        }

        @Test("All-timeout response: nodes returned as isSuccess=false with nil latency")
        func allTimeoutNodesReturnedWithFailure() async throws {
            let submitJSON = try MockURLProtocol.loadFixture(named: "globalping-submit-success.json")
            let resultsJSON = try MockURLProtocol.loadFixture(named: "globalping-result-all-timeout.json")
            let session = MockURLProtocol.makeSession { request in
                let data = request.httpMethod == "POST" ? Data(submitJSON.utf8) : Data(resultsJSON.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let service = WorldPingService(session: session)
            var results: [WorldPingLocationResult] = []
            for await result in await service.ping(host: "unreachable.example", maxNodes: 5) {
                results.append(result)
            }

            #expect(results.count == 5, "All 5 nodes should still be returned even on timeout")
            #expect(results.allSatisfy { !$0.isSuccess }, "All timeout nodes should have isSuccess=false")
            #expect(results.allSatisfy { $0.latencyMs == nil }, "All timeout nodes should have nil latency")
        }

        @Test("HTTP error on submit finishes stream empty and sets lastError")
        func httpErrorOnSubmitFinishesEmptyWithLastError() async throws {
            let session = MockURLProtocol.makeSession { request in
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("{\"error\": \"internal server error\"}".utf8))
            }

            let service = WorldPingService(session: session)
            var results: [WorldPingLocationResult] = []
            for await result in await service.ping(host: "google.com", maxNodes: 5) {
                results.append(result)
            }

            #expect(results.isEmpty, "HTTP error should NOT yield a fake result — stream finishes empty so ViewModel sets errorMessage")
            #expect(service.lastError != nil, "lastError should be set with the error description")
            #expect(service.lastError?.isEmpty == false, "lastError should contain a meaningful message")
        }

        @Test("Network error on submit finishes stream empty and sets lastError")
        func networkErrorOnSubmitFinishesEmptyWithLastError() async throws {
            let session = MockURLProtocol.makeSession { _ in
                throw URLError(.notConnectedToInternet)
            }

            let service = WorldPingService(session: session)
            var results: [WorldPingLocationResult] = []
            for await result in await service.ping(host: "google.com", maxNodes: 5) {
                results.append(result)
            }

            #expect(results.isEmpty, "Network error should NOT yield a fake result — stream finishes empty")
            #expect(service.lastError != nil, "lastError should be set on network failure")
        }

        @Test("Results are sorted by ascending latency")
        func resultsAreSortedByLatency() async throws {
            let submitJSON = try MockURLProtocol.loadFixture(named: "globalping-submit-success.json")
            let resultsJSON = try MockURLProtocol.loadFixture(named: "globalping-result-complete.json")
            let session = MockURLProtocol.makeSession { request in
                let data = request.httpMethod == "POST" ? Data(submitJSON.utf8) : Data(resultsJSON.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, data)
            }

            let service = WorldPingService(session: session)
            var results: [WorldPingLocationResult] = []
            for await result in await service.ping(host: "test.com", maxNodes: 5) {
                results.append(result)
            }

            let latencies = results.compactMap { $0.latencyMs }
            #expect(latencies == latencies.sorted(), "Results should be sorted by ascending latency: \(latencies)")
        }
    }

    // MARK: - GeoLocationService

    @Suite("GeoLocationService Contract")
    struct GeoLocationServiceContractTests {

        init() { MockURLProtocol.requestHandler = nil }

        @Test("Success response: real decoder maps all ip-api.com fields to GeoLocation")
        func successResponseMapsAllFields() async throws {
            let json = try MockURLProtocol.loadFixture(named: "ip-api-success.json")
            let session = MockURLProtocol.makeSession { request in
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(json.utf8))
            }

            let service = GeoLocationService(session: session)
            let location = try await service.lookup(ip: "8.8.8.8")

            #expect(location.ip == "8.8.8.8")
            #expect(location.country == "United States")
            #expect(location.countryCode == "US")
            #expect(location.region == "CA")
            #expect(location.city == "Mountain View")
            #expect(abs(location.latitude - 37.386) < 0.001)
            #expect(abs(location.longitude - -122.0838) < 0.001)
            #expect(location.isp == "Google LLC")
        }

        @Test("Success response: result is cached — second call does not hit network")
        func resultIsCached() async throws {
            let json = try MockURLProtocol.loadFixture(named: "ip-api-success.json")
            var requestCount = 0
            let session = MockURLProtocol.makeSession { request in
                requestCount += 1
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(json.utf8))
            }

            let service = GeoLocationService(session: session)
            _ = try await service.lookup(ip: "8.8.8.8")
            _ = try await service.lookup(ip: "8.8.8.8")

            #expect(requestCount == 1, "Second lookup for same IP should use cache, not make another HTTP request")
        }

        @Test("status=fail response: throws GeoLocationError.lookupFailed with message")
        func failStatusThrowsLookupFailed() async throws {
            let json = try MockURLProtocol.loadFixture(named: "ip-api-failure.json")
            let session = MockURLProtocol.makeSession { request in
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data(json.utf8))
            }

            let service = GeoLocationService(session: session)
            do {
                _ = try await service.lookup(ip: "192.168.1.1")
                Issue.record("Expected GeoLocationError.lookupFailed to be thrown")
            } catch let error as GeoLocationError {
                if case .lookupFailed(let message) = error {
                    #expect(message == "reserved range")
                } else {
                    Issue.record("Expected lookupFailed, got: \(error)")
                }
            }
        }

        @Test("HTTP 429 (rate limit): throws GeoLocationError.httpError")
        func http429ThrowsHTTPError() async throws {
            let session = MockURLProtocol.makeSession { request in
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 429, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("{\"status\":\"fail\",\"message\":\"rate limited\"}".utf8))
            }

            let service = GeoLocationService(session: session)
            do {
                _ = try await service.lookup(ip: "1.2.3.4")
                Issue.record("Expected GeoLocationError.httpError to be thrown")
            } catch let error as GeoLocationError {
                if case .httpError = error { } else {
                    Issue.record("Expected httpError, got: \(error)")
                }
            }
        }

        @Test("HTTP 500 (server error): throws GeoLocationError.httpError")
        func http500ThrowsHTTPError() async throws {
            let session = MockURLProtocol.makeSession { request in
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 500, httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data("{}".utf8))
            }

            let service = GeoLocationService(session: session)
            do {
                _ = try await service.lookup(ip: "1.2.3.4")
                Issue.record("Expected error to be thrown for HTTP 500")
            } catch let error as GeoLocationError {
                if case .httpError = error { } else {
                    Issue.record("Expected httpError, got: \(error)")
                }
            }
        }

        @Test("Network error: throws URLError, not a silent empty result")
        func networkErrorThrows() async throws {
            let session = MockURLProtocol.makeSession { _ in
                throw URLError(.notConnectedToInternet)
            }

            let service = GeoLocationService(session: session)
            do {
                _ = try await service.lookup(ip: "8.8.8.8")
                Issue.record("Expected URLError to be thrown")
            } catch is URLError {
                // correct
            }
        }

        @Test("Malformed JSON response: throws, not a silent nil result")
        func malformedJSONThrows() async throws {
            let session = MockURLProtocol.makeSession { request in
                let response = HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200, httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                return (response, Data("not valid json".utf8))
            }

            let service = GeoLocationService(session: session)
            do {
                _ = try await service.lookup(ip: "8.8.8.8")
                Issue.record("Expected an error to be thrown for malformed JSON")
            } catch {
                // Any error thrown is correct behavior — no silent nil
            }
        }
    }
}
