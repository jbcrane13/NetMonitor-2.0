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

    // MARK: - Additional Computed Property Edge Cases (6A)

    @Test func averageLatencyWithMixedNilLatency() {
        // Multiple results where some have nil latency — only non-nil counted
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 100.0, isSuccess: true),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "c", country: "JP", city: "Tokyo", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "d", country: "BR", city: "Sao Paulo", latencyMs: 200.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        // (100 + 200) / 2 = 150
        #expect(result.averageLatencyMs == 150.0)
    }

    @Test func minimumLatencySingleResult() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 42.5, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.minimumLatencyMs == 42.5)
    }

    @Test func minimumLatencyAllNilReturnsNil() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: nil, isSuccess: false),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.minimumLatencyMs == nil)
    }

    @Test func maximumLatencyWithMixedNilValues() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: 75.0, isSuccess: true),
            WorldPingLocationResult(id: "c", country: "JP", city: "Tokyo", latencyMs: 150.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.maximumLatencyMs == 150.0)
    }

    @Test func maximumLatencySingleResult() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 99.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.maximumLatencyMs == 99.0)
    }

    @Test func successRateAllSuccessful() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 10.0, isSuccess: true),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: 20.0, isSuccess: true),
            WorldPingLocationResult(id: "c", country: "JP", city: "Tokyo", latencyMs: 30.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.successRate == 1.0)
    }

    @Test func successRateAllFailed() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: nil, isSuccess: false),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: nil, isSuccess: false),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.successRate == 0.0)
    }

    @Test func averageLatencyPrecisionWithManyNodes() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 10.0, isSuccess: true),
            WorldPingLocationResult(id: "b", country: "DE", city: "Berlin", latencyMs: 20.0, isSuccess: true),
            WorldPingLocationResult(id: "c", country: "JP", city: "Tokyo", latencyMs: 33.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        // (10 + 20 + 33) / 3 = 21.0
        #expect(result.averageLatencyMs == 21.0)
    }

    @Test func successCountWithSingleNode() {
        let nodes = [
            WorldPingLocationResult(id: "a", country: "US", city: "NYC", latencyMs: 10.0, isSuccess: true),
        ]
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: nodes)
        #expect(result.successCount == 1)
        #expect(result.successRate == 1.0)
    }

    @Test func emptyResultsArrayAllPropertiesAtDefault() {
        let result = WorldPingCheckResult(host: "test.com", requestId: "r1", locationResults: [])
        #expect(result.averageLatencyMs == nil)
        #expect(result.minimumLatencyMs == nil)
        #expect(result.maximumLatencyMs == nil)
        #expect(result.successCount == 0)
        #expect(result.successRate == 0.0)
    }
}
