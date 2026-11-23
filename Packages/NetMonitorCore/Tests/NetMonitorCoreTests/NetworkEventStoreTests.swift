import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - NetworkEvent model (#491 S1)

@Suite("NetworkEvent coding")
struct NetworkEventCodingTests {
    /// What builds before #491 wrote: no device or network ID, dates as reference-date seconds.
    @Test func oldJSONDecodesWithNilIDs() throws {
        let json = """
        {"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","type":"deviceJoined","timestamp":700000000,\
        "title":"Device Joined: Printer","details":"192.168.1.30","severity":"success"}
        """
        let event = try JSONDecoder().decode(NetworkEvent.self, from: Data(json.utf8))
        #expect(event.title == "Device Joined: Printer")
        #expect(event.timestamp == Date(timeIntervalSinceReferenceDate: 700_000_000))
        #expect(event.deviceID == nil)
        #expect(event.networkProfileID == nil)
    }

    @Test func idsRoundTrip() throws {
        let device = UUID()
        let network = UUID()
        let event = NetworkEvent(type: .deviceLeft, title: "Left", deviceID: device, networkProfileID: network)
        let decoded = try JSONDecoder().decode(NetworkEvent.self, from: JSONEncoder().encode(event))
        #expect(decoded.deviceID == device)
        #expect(decoded.networkProfileID == network)
    }
}

// MARK: - Where history files live (#491 S1)

@Suite("HistoryFileLocation")
struct HistoryFileLocationTests {
    let tmp = URL(fileURLWithPath: "/tmp/fake-tmp", isDirectory: true)
    let support = URL(fileURLWithPath: "/fake/Application Support", isDirectory: true)

    func location(_ arguments: [String], _ environment: [String: String] = [:], pid: Int32 = 42) -> HistoryFileLocation {
        HistoryFileLocation(
            arguments: arguments, environment: environment,
            temporaryDirectory: tmp, applicationSupportDirectory: support, processID: pid
        )
    }

    @Test func normalLaunchUsesApplicationSupport() {
        let result = location(["/app"])
        #expect(result.directory.path == "/fake/Application Support/NetMonitor")
        #expect(result.resetRequested == false)
    }

    @Test func uiTestingUsesOneFixedDirectoryThatSurvivesRelaunch() {
        let first = location(["/app", "--uitesting"], pid: 1)
        let relaunch = location(["/app", "--uitesting"], pid: 2)
        #expect(first.directory.path == "/tmp/fake-tmp/netmonitor-uitest-history")
        #expect(relaunch.directory == first.directory)
    }

    @Test func unitTestHostUsesAPerProcessDirectory() {
        let env = ["XCTestConfigurationFilePath": "/x.xctestconfiguration"]
        let one = location(["/app"], env, pid: 7)
        let other = location(["/app"], env, pid: 8)
        #expect(one.directory.path == "/tmp/fake-tmp/netmonitor-history-7")
        #expect(one.directory != other.directory)
    }

    @Test func inMemoryStoreUsesAPerProcessDirectory() {
        #expect(location(["/app", "--in-memory-store"], pid: 9).directory.path == "/tmp/fake-tmp/netmonitor-history-9")
    }

    /// macOS UI tests pass both; the fixed directory wins so a relaunch sees the same files.
    @Test func uiTestingWinsOverInMemoryStore() {
        let result = location(["/app", "--in-memory-store", "--uitesting"])
        #expect(result.directory.path == "/tmp/fake-tmp/netmonitor-uitest-history")
    }

    @Test func resetFlagsRequestAReset() {
        #expect(location(["/app", "--uitesting", "--reset-history-files"]).resetRequested)
        // iOS's --uitesting-reset implies it, and is itself a UI-test launch.
        let iOSReset = location(["/app", "--uitesting-reset"])
        #expect(iOSReset.resetRequested)
        #expect(iOSReset.directory.path == "/tmp/fake-tmp/netmonitor-uitest-history")
    }
}

// MARK: - File-backed NetworkEventService (#491 S1)

/// A temp directory per test, and the legacy UserDefaults blob builds before #491 wrote.
struct EventFileFixture {
    let directory = FileManager.default.temporaryDirectory
        .appending(path: "NetworkEventStoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    var fileURL: URL { directory.appending(path: "network-events.json") }
    let suiteName = "NetworkEventStoreTests.\(UUID().uuidString)"
    var legacyDefaults: UserDefaults { UserDefaults(suiteName: suiteName)! }
    static let legacyKey = "com.netmonitor.networkEvents"

    /// Two good events (newest first) around one that isn't a valid event.
    static let blobWithCorruptElement = Data("""
    [{"id":"11111111-1111-1111-1111-111111111111","type":"deviceJoined","timestamp":700000200,\
    "title":"Legacy newer","severity":"success"},
    {"id":"not-a-uuid","type":"deviceJoined"},
    {"id":"22222222-2222-2222-2222-222222222222","type":"scanComplete","timestamp":700000100,\
    "title":"Legacy older","details":"3 devices","severity":"info"}]
    """.utf8)

    func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
        UserDefaults().removePersistentDomain(forName: suiteName)
    }

    func writeFile(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    func savedTitles() throws -> [String] {
        try JSONDecoder().decode([NetworkEvent].self, from: Data(contentsOf: fileURL)).map(\.title)
    }
}

@Suite("NetworkEventService file store", .serialized)
struct NetworkEventFileStoreTests {
    @Test func lossyDecodeSkipsTheBadElement() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(EventFileFixture.blobWithCorruptElement)

        let service = NetworkEventService(fileURL: fixture.fileURL)

        #expect(service.events.map(\.title) == ["Legacy newer", "Legacy older"])
    }

    @Test func unknownEventTypeIsSkippedNotFatal() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(Data("""
        [{"id":"33333333-3333-3333-3333-333333333333","type":"fromAFutureBuild","timestamp":1,"title":"x","severity":"info"},
        {"id":"44444444-4444-4444-4444-444444444444","type":"toolRun","timestamp":2,"title":"kept","severity":"info"}]
        """.utf8))

        #expect(NetworkEventService(fileURL: fixture.fileURL).events.map(\.title) == ["kept"])
    }

    @Test func migratesTheLegacyBlobAndKeepsTheLegacyKey() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        fixture.legacyDefaults.set(EventFileFixture.blobWithCorruptElement, forKey: EventFileFixture.legacyKey)

        let service = NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults)

        #expect(service.events.map(\.title) == ["Legacy newer", "Legacy older"])
        // Written synchronously at migration, without waiting for a flush.
        #expect(try fixture.savedTitles() == ["Legacy newer", "Legacy older"])
        // Unchanged, so an older build still sees its events after a downgrade.
        #expect(fixture.legacyDefaults.data(forKey: EventFileFixture.legacyKey) == EventFileFixture.blobWithCorruptElement)
    }

    @Test func anExistingFileWinsOverTheLegacyBlob() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(Data("[]".utf8))
        fixture.legacyDefaults.set(EventFileFixture.blobWithCorruptElement, forKey: EventFileFixture.legacyKey)

        #expect(NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults).events.isEmpty)
    }

    @Test func aFailedMigrationWriteIsRetriedNextLaunch() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        fixture.legacyDefaults.set(EventFileFixture.blobWithCorruptElement, forKey: EventFileFixture.legacyKey)
        // A plain file where the directory should be makes the write fail.
        try FileManager.default.createDirectory(at: fixture.directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: fixture.directory)

        let failed = NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults)
        #expect(failed.events.count == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))

        try FileManager.default.removeItem(at: fixture.directory)
        let retried = NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults)
        #expect(retried.events.count == 2)
        #expect(try fixture.savedTitles() == ["Legacy newer", "Legacy older"])
    }

    @Test func writesWaitForTheDebounceUntilFlushed() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 3600)

        service.log(type: .toolRun, title: "first")
        service.log(type: .toolRun, title: "second")
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))

        service.flush()
        #expect(try fixture.savedTitles() == ["second", "first"])
    }

    @Test func aDebouncedWriteLandsWithoutAFlush() async throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 0.05)

        service.log(type: .toolRun, title: "debounced")

        for _ in 0..<100 where !FileManager.default.fileExists(atPath: fixture.fileURL.path) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(try fixture.savedTitles() == ["debounced"])
    }

    @Test func eventsSurviveARelaunch() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 3600)
        service.log(NetworkEvent(type: .deviceJoined, title: "Joined", deviceID: UUID(), networkProfileID: UUID()))
        service.flush()

        let relaunched = NetworkEventService(fileURL: fixture.fileURL)
        #expect(relaunched.events.map(\.id) == service.events.map(\.id))
        #expect(relaunched.events.first?.deviceID == service.events.first?.deviceID)
    }

    /// Clearing leaves an empty file, so the next launch doesn't migrate the legacy blob again.
    @Test func clearAllWritesAnEmptyFileAtOnce() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        fixture.legacyDefaults.set(EventFileFixture.blobWithCorruptElement, forKey: EventFileFixture.legacyKey)
        let service = NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults, debounce: 3600)

        service.clearAll()

        #expect(try fixture.savedTitles().isEmpty)
        #expect(NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults).events.isEmpty)
    }

    @Test func pruningIsWrittenAtOnce() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 3600)
        let now = Date()
        service.log(NetworkEvent(type: .toolRun, timestamp: now.addingTimeInterval(-10 * 86400), title: "old"))
        service.log(NetworkEvent(type: .toolRun, timestamp: now, title: "new"))

        service.removeEvents(olderThan: now.addingTimeInterval(-7 * 86400))

        #expect(try fixture.savedTitles() == ["new"])
    }

    @Test func keepsTheNewest20000Events() {
        let service = NetworkEventService()
        let start = Date(timeIntervalSinceReferenceDate: 0)
        for index in 0...20_000 {
            service.log(NetworkEvent(type: .toolRun, timestamp: start.addingTimeInterval(Double(index)), title: "\(index)"))
        }
        #expect(NetworkEventService.eventCeiling == 20_000)
        #expect(service.events.count == 20_000)
        #expect(service.events.first?.title == "20000")
        #expect(service.events.last?.title == "1")
    }

    @Test func loadingKeepsOnlyTheNewestUpToTheCeiling() throws {
        let fixture = EventFileFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(EventFileFixture.blobWithCorruptElement)

        #expect(NetworkEventService(fileURL: fixture.fileURL, ceiling: 1).events.map(\.title) == ["Legacy newer"])
    }

    @Test func anInMemoryServiceNeverWrites() {
        let service = NetworkEventService()
        service.log(type: .toolRun, title: "memory only")
        service.flush()
        #expect(service.events.count == 1)
    }
}
