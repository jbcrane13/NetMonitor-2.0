import Testing
import Foundation
@testable import NetMonitorCore

// MARK: - WorldPingCheckResult Tests

@Suite("WorldPingCheckResult")
struct WorldPingCheckResultTests {

    // MARK: - Init and Properties

    @Test func initStoresAllProperties() {
        let date = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let result = WorldPingCheckResult(
            host: "example.com",
            requestId: "req-abc-123",
            locationResults: [],
            completedAt: date
        )
        #expect(result.host == "example.com")
        #expect(result.requestId == "req-abc-123")
        #expect(result.locationResults.isEmpty)
        #expect(result.completedAt == date)
    }

    @Test func defaultCompletedAtIsNearNow() {
        let before = Date()
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: [])
        let after = Date()
        #expect(result.completedAt >= before)
        #expect(result.completedAt <= after)
    }

    // MARK: - Latency Aggregation

    @Test func averageLatencyAcrossSuccessfulNodes() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 10.0, isSuccess: true),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: 30.0, isSuccess: true),
            WorldPingLocationResult(id: "c", country: "JP", city: "Tokyo", latencyMs: 20.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.averageLatencyMs == 20.0)
    }

    @Test func minimumLatencyReturnsLowest() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 50.0, isSuccess: true),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: 12.5, isSuccess: true),
            WorldPingLocationResult(id: "c", country: "JP", city: "Tokyo", latencyMs: 80.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.minimumLatencyMs == 12.5)
    }

    @Test func maximumLatencyReturnsHighest() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 50.0, isSuccess: true),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: 12.5, isSuccess: true),
            WorldPingLocationResult(id: "c", country: "JP", city: "Tokyo", latencyMs: 200.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.maximumLatencyMs == 200.0)
    }

    @Test func nodesWithNilLatencyExcludedFromAggregates() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 40.0, isSuccess: true),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "c", country: "JP", city: "Tokyo", latencyMs: 60.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.averageLatencyMs == 50.0)
        #expect(result.minimumLatencyMs == 40.0)
        #expect(result.maximumLatencyMs == 60.0)
    }

    // MARK: - Empty Nodes Handling

    @Test func emptyNodesAverageLatencyIsNil() {
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: [])
        #expect(result.averageLatencyMs == nil)
    }

    @Test func emptyNodesMinLatencyIsNil() {
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: [])
        #expect(result.minimumLatencyMs == nil)
    }

    @Test func emptyNodesMaxLatencyIsNil() {
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: [])
        #expect(result.maximumLatencyMs == nil)
    }

    @Test func emptyNodesSuccessRateIsZero() {
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: [])
        #expect(result.successRate == 0.0)
    }

    @Test func allFailedNodesAllLatencyNilReturnsNilAggregates() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: nil, isSuccess: false),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.averageLatencyMs == nil)
        #expect(result.minimumLatencyMs == nil)
        #expect(result.maximumLatencyMs == nil)
        #expect(result.successCount == 0)
        #expect(result.successRate == 0.0)
    }

    // MARK: - Success Metrics

    @Test func successCountCountsOnlySuccessfulNodes() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 10.0, isSuccess: true),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "c", country: "JP", city: "Tokyo", latencyMs: 20.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.successCount == 2)
    }

    @Test func successRateIsRatioOfSuccessful() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 10.0, isSuccess: true),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "c", country: "AU", city: "Sydney", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "d", country: "JP", city: "Tokyo", latencyMs: 20.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.successRate == 0.5)
    }
}
