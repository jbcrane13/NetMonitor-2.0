import Foundation
import Observation
import Testing
@testable import NetMonitorCore

// MARK: - Health-score history (#491 S5)

@Suite("HealthScoreHistoryStore")
struct HealthScoreHistoryStoreTests {
    let home = UUID()
    let office = UUID()
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func score(_ value: Int, _ grade: String = "B") -> NetworkHealthScore {
        NetworkHealthScore(score: value, grade: grade)
    }

    @Test func recordsOneSamplePerNetworkPerFifteenMinutes() {
        let store = HealthScoreHistoryStore()
        #expect(store.record(score(80), networkProfileID: home, at: start))
        #expect(!store.record(score(60), networkProfileID: home, at: start.addingTimeInterval(14 * 60)))
        #expect(store.record(score(70), networkProfileID: home, at: start.addingTimeInterval(15 * 60)))
        #expect(store.samples(for: home).map(\.score) == [80, 70])
    }

    @Test func throttleIsPerNetwork() {
        let store = HealthScoreHistoryStore()
        store.record(score(80), networkProfileID: home, at: start)
        #expect(store.record(score(55, "D"), networkProfileID: office, at: start.addingTimeInterval(60)))
        let sample = store.samples(for: office).first
        #expect(sample?.score == 55)
        #expect(sample?.grade == "D")
        #expect(sample?.networkProfileID == office)
        #expect(sample?.timestamp == start.addingTimeInterval(60))
        #expect(store.samples(for: home).count == 1)
    }

    @Test func samplesAreOldestFirst() {
        let store = HealthScoreHistoryStore()
        // Recorded out of order, as a seed or a clock change can.
        store.record(score(70), networkProfileID: home, at: start.addingTimeInterval(3600))
        store.record(score(90), networkProfileID: home, at: start)
        #expect(store.samples(for: home).map(\.score) == [90, 70])
    }

    @Test func removesSamplesOlderThanTheCutoff() {
        let store = HealthScoreHistoryStore()
        store.record(score(50), networkProfileID: home, at: start)
        store.record(score(60), networkProfileID: office, at: start.addingTimeInterval(3600))
        store.record(score(70), networkProfileID: home, at: start.addingTimeInterval(7200))
        store.removeSamples(olderThan: start.addingTimeInterval(3600))
        #expect(store.samples(for: home).map(\.score) == [70])
        #expect(store.samples(for: office).map(\.score) == [60])
    }

    @Test func keepsOnlyTheNewestSamplesUpToTheCeiling() {
        let store = HealthScoreHistoryStore(ceiling: 3)
        for index in 0..<5 {
            store.record(score(index), networkProfileID: home, at: start.addingTimeInterval(Double(index) * 3600))
        }
        #expect(store.samples(for: home).map(\.score) == [2, 3, 4])
    }

    @Test func readersAreToldWhenAnotherWriterRecords() {
        let store = HealthScoreHistoryStore()
        let changed = Flag()
        withObservationTracking {
            _ = store.samples(for: home)
        } onChange: {
            changed.set()
        }
        store.record(score(80), networkProfileID: home, at: start)
        #expect(changed.isSet)
    }

    @Test func throttledRecordChangesNothingObservable() {
        let store = HealthScoreHistoryStore()
        store.record(score(80), networkProfileID: home, at: start)
        let before = store.revision
        store.record(score(60), networkProfileID: home, at: start.addingTimeInterval(60))
        #expect(store.revision == before)
    }

    @Test func uiTestSeedReplacesTheHistoryEndingAMinuteAgo() {
        let store = HealthScoreHistoryStore()
        store.record(score(10), networkProfileID: home, at: start.addingTimeInterval(-86400))
        store.seedForUITests(count: 5, networkProfileID: home, now: start)
        let samples = store.samples(for: home)
        #expect(samples.map(\.score) == [72, 81, 64, 88, 79])
        #expect(samples.last?.timestamp == start.addingTimeInterval(-60))
        // The dashboard's own refresh right after launch is throttled.
        #expect(!store.record(score(50), networkProfileID: home, at: start))
    }

    @Test func ceilingIsTwentyThousand() {
        #expect(HealthScoreHistoryStore.sampleCeiling == 20_000)
    }
}

private final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.withLock { value } }
    func set() { lock.withLock { value = true } }
}

// MARK: - Saving to a file (#491 S5, D2 contract)

@Suite("HealthScoreHistoryStore file")
struct HealthScoreHistoryStoreFileTests {
    let network = UUID()
    let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func makeDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appending(path: "health-history-tests-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func flushSavesSoANewStoreLoadsTheSamples() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: HealthScoreHistoryStore.fileName)
        // A long debounce: only flush() can have written it.
        let store = HealthScoreHistoryStore(fileURL: url, debounce: 3600)
        store.record(NetworkHealthScore(score: 77, grade: "C"), networkProfileID: network, at: start)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        store.flush()
        let reloaded = HealthScoreHistoryStore(fileURL: url)
        #expect(reloaded.samples(for: network).map(\.score) == [77])
    }

    @Test func debouncedWriteLandsWithoutFlush() async throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: HealthScoreHistoryStore.fileName)
        let store = HealthScoreHistoryStore(fileURL: url, debounce: 0.05)
        store.record(NetworkHealthScore(score: 66, grade: "C"), networkProfileID: network, at: start)
        for _ in 0..<100 where !FileManager.default.fileExists(atPath: url.path) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(HealthScoreHistoryStore(fileURL: url).samples(for: network).map(\.score) == [66])
    }

    @Test func pruneSavesAtOnce() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: HealthScoreHistoryStore.fileName)
        let store = HealthScoreHistoryStore(fileURL: url, debounce: 3600)
        store.record(NetworkHealthScore(score: 10, grade: "F"), networkProfileID: network, at: start)
        store.record(NetworkHealthScore(score: 90, grade: "A"), networkProfileID: network, at: start.addingTimeInterval(3600))
        store.removeSamples(olderThan: start.addingTimeInterval(60))
        #expect(HealthScoreHistoryStore(fileURL: url).samples(for: network).map(\.score) == [90])
    }

    @Test func skipsElementsThatDoNotDecode() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: HealthScoreHistoryStore.fileName)
        let json = """
        [{"id":"\(UUID())","networkProfileID":"\(network)","timestamp":800000000,"score":81,"grade":"B"},
        {"id":"not-a-uuid","score":"x"},
        {"id":"\(UUID())","networkProfileID":"\(network)","timestamp":800003600,"score":64,"grade":"C"}]
        """
        try Data(json.utf8).write(to: url)
        #expect(HealthScoreHistoryStore(fileURL: url).samples(for: network).map(\.score) == [81, 64])
    }

    @Test func unreadableFileIsMovedAsideNotOverwritten() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: HealthScoreHistoryStore.fileName)
        try Data("not json".utf8).write(to: url)
        let store = HealthScoreHistoryStore(fileURL: url)
        #expect(store.samples(for: network).isEmpty)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        #expect(names.contains { $0.hasPrefix("health-score-history.corrupt-") })
    }

    @Test func clearAllEmptiesTheFile() throws {
        let dir = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appending(path: HealthScoreHistoryStore.fileName)
        let store = HealthScoreHistoryStore(fileURL: url, debounce: 3600)
        store.record(NetworkHealthScore(score: 50, grade: "D"), networkProfileID: network, at: start)
        store.clearAll()
        #expect(HealthScoreHistoryStore(fileURL: url).samples(for: network).isEmpty)
    }
}

@Suite("HealthScoreSample chart domain")
struct HealthScoreSampleChartDomainTests {
    func samples(_ scores: [Int]) -> [HealthScoreSample] {
        scores.map { HealthScoreSample(networkProfileID: UUID(), timestamp: Date(timeIntervalSinceReferenceDate: 0), score: $0, grade: "B") }
    }

    @Test func padsTheSampleRangeByTenPoints() {
        #expect(HealthScoreSample.chartDomain(samples([64, 88, 72])) == 54...98)
    }

    @Test func staysWithinZeroToHundred() {
        #expect(HealthScoreSample.chartDomain(samples([3, 97])) == 0...100)
    }

    @Test func emptyIsTheFullScale() {
        #expect(HealthScoreSample.chartDomain([]) == 0...100)
    }
}
