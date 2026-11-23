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

    @Test func legacyEventsComeFromTheAppOnlyOnANormalLaunch() {
        #expect(location(["/app"]).legacyDefaults === UserDefaults.standard)
        let uiTest = location(["/app", "--uitesting"]).legacyDefaults
        #expect(uiTest != nil && uiTest !== UserDefaults.standard)
        #expect(location(["/app"], ["XCTestConfigurationFilePath": "/x"]).legacyDefaults == nil)
    }

    /// A location under a fresh temp directory with one saved file, `events.json`.
    func locationWithSavedFile(_ arguments: [String]) throws -> (HistoryFileLocation, URL) {
        let root = FileManager.default.temporaryDirectory.appending(path: "HistoryFileLocationTests-\(UUID().uuidString)")
        let result = HistoryFileLocation(
            arguments: arguments, environment: [:],
            temporaryDirectory: root, applicationSupportDirectory: root, processID: 1
        )
        try FileManager.default.createDirectory(at: result.directory, withIntermediateDirectories: true)
        let file = result.fileURL(named: "events.json")
        try Data("[]".utf8).write(to: file)
        return (result, root)
    }

    @Test func lookingUpAFileNeverDeletesIt() throws {
        let (resetting, root) = try locationWithSavedFile(["/app", "--reset-history-files"])
        defer { try? FileManager.default.removeItem(at: root) }

        let file = resetting.fileURL(named: "events.json")

        #expect(FileManager.default.fileExists(atPath: file.path))
    }

    @Test func resetIfRequestedDeletesOnlyWhenAsked() throws {
        let (keeping, keepRoot) = try locationWithSavedFile(["/app"])
        let (resetting, resetRoot) = try locationWithSavedFile(["/app", "--reset-history-files"])
        defer {
            try? FileManager.default.removeItem(at: keepRoot)
            try? FileManager.default.removeItem(at: resetRoot)
        }

        keeping.resetIfRequested(fileNamed: "events.json")
        resetting.resetIfRequested(fileNamed: "events.json")

        #expect(FileManager.default.fileExists(atPath: keeping.fileURL(named: "events.json").path))
        #expect(!FileManager.default.fileExists(atPath: resetting.fileURL(named: "events.json").path))
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
    let legacyDefaults: UserDefaults
    static let legacyKey = NetworkEventService.legacyDefaultsKey

    init() throws {
        legacyDefaults = try #require(UserDefaults(suiteName: suiteName))
    }

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
        legacyDefaults.removePersistentDomain(forName: suiteName)
    }

    func writeFile(_ data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: fileURL)
    }

    /// A plain file where the directory should be makes every write fail.
    func blockDirectory() throws {
        try FileManager.default.createDirectory(at: directory.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data().write(to: directory)
    }

    func corruptFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasPrefix("network-events.corrupt-") }
    }

    func savedTitles() throws -> [String] {
        try JSONDecoder().decode([NetworkEvent].self, from: Data(contentsOf: fileURL)).map(\.title)
    }
}

@Suite("NetworkEventService file store", .serialized)
struct NetworkEventFileStoreTests {
    @Test func lossyDecodeSkipsTheBadElement() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(EventFileFixture.blobWithCorruptElement)

        let service = NetworkEventService(fileURL: fixture.fileURL)

        #expect(service.events.map(\.title) == ["Legacy newer", "Legacy older"])
    }

    @Test func unknownEventTypeIsSkippedNotFatal() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(Data("""
        [{"id":"33333333-3333-3333-3333-333333333333","type":"fromAFutureBuild","timestamp":1,"title":"x","severity":"info"},
        {"id":"44444444-4444-4444-4444-444444444444","type":"toolRun","timestamp":2,"title":"kept","severity":"info"}]
        """.utf8))

        #expect(NetworkEventService(fileURL: fixture.fileURL).events.map(\.title) == ["kept"])
    }

    @Test func migratesTheLegacyBlobAndKeepsTheLegacyKey() throws {
        let fixture = try EventFileFixture()
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
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(Data("[]".utf8))
        fixture.legacyDefaults.set(EventFileFixture.blobWithCorruptElement, forKey: EventFileFixture.legacyKey)

        #expect(NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults).events.isEmpty)
    }

    @Test func aFailedMigrationWriteIsRetriedNextLaunch() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        fixture.legacyDefaults.set(EventFileFixture.blobWithCorruptElement, forKey: EventFileFixture.legacyKey)
        try fixture.blockDirectory()

        let failed = NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults)
        #expect(failed.events.count == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))

        try FileManager.default.removeItem(at: fixture.directory)
        let retried = NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults)
        #expect(retried.events.count == 2)
        #expect(try fixture.savedTitles() == ["Legacy newer", "Legacy older"])
    }

    @Test func writesWaitForTheDebounceUntilFlushed() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 3600)

        service.log(type: .toolRun, title: "first")
        service.log(type: .toolRun, title: "second")
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))

        service.flush()
        #expect(try fixture.savedTitles() == ["second", "first"])
    }

    @Test func aDebouncedWriteLandsWithoutAFlush() async throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 0.05)

        service.log(type: .toolRun, title: "debounced")

        await waitUntil { FileManager.default.fileExists(atPath: fixture.fileURL.path) }
        #expect(try fixture.savedTitles() == ["debounced"])
    }

    @Test func eventsSurviveARelaunch() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 3600)
        service.log(NetworkEvent(type: .deviceJoined, title: "Joined", deviceID: UUID(), networkProfileID: UUID()))
        service.flush()

        let relaunched = NetworkEventService(fileURL: fixture.fileURL)
        #expect(relaunched.events.map(\.id) == service.events.map(\.id))
        #expect(relaunched.events.first?.deviceID == service.events.first?.deviceID)
    }

    /// Clearing leaves an empty file and removes the legacy blob, so neither the next launch nor
    /// an older build brings the events back.
    @Test func clearAllWritesAnEmptyFileAtOnceAndRemovesTheLegacyEvents() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        fixture.legacyDefaults.set(EventFileFixture.blobWithCorruptElement, forKey: EventFileFixture.legacyKey)
        let service = NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults, debounce: 3600)

        service.clearAll()

        #expect(try fixture.savedTitles().isEmpty)
        #expect(fixture.legacyDefaults.data(forKey: EventFileFixture.legacyKey) == nil)
        #expect(NetworkEventService(fileURL: fixture.fileURL, legacyDefaults: fixture.legacyDefaults).events.isEmpty)
    }

    @Test func pruningIsWrittenAtOnce() throws {
        let fixture = try EventFileFixture()
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
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(EventFileFixture.blobWithCorruptElement)

        #expect(NetworkEventService(fileURL: fixture.fileURL, ceiling: 1).events.map(\.title) == ["Legacy newer"])
    }

    @Test func anUnreadableFileIsMovedAsideNotOverwritten() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        let garbage = Data("{ not an array".utf8)
        try fixture.writeFile(garbage)

        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 3600)
        #expect(service.events.isEmpty)
        service.log(type: .toolRun, title: "after")
        service.flush()

        #expect(try fixture.savedTitles() == ["after"])
        let aside = try fixture.corruptFiles()
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: fixture.directory.appending(path: aside[0])) == garbage)
    }

    @Test func onlyTheLatestUnreadableFileIsKept() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        try fixture.writeFile(Data("first".utf8))
        _ = NetworkEventService(fileURL: fixture.fileURL)
        try fixture.writeFile(Data("second".utf8))
        _ = NetworkEventService(fileURL: fixture.fileURL)

        let aside = try fixture.corruptFiles()
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: fixture.directory.appending(path: aside[0])) == Data("second".utf8))
    }

    /// A write that fails (disk full, say) is retried by the next flush instead of being dropped.
    @Test func aFailedWriteIsRetriedByTheNextFlush() throws {
        let fixture = try EventFileFixture()
        defer { fixture.cleanUp() }
        let service = NetworkEventService(fileURL: fixture.fileURL, debounce: 3600)
        try fixture.blockDirectory()
        service.log(type: .toolRun, title: "kept")
        service.flush()
        #expect(!FileManager.default.fileExists(atPath: fixture.fileURL.path))

        try FileManager.default.removeItem(at: fixture.directory)
        service.flush()

        #expect(try fixture.savedTitles() == ["kept"])
    }

    @Test func anInMemoryServiceNeverWrites() {
        let service = NetworkEventService()
        service.log(type: .toolRun, title: "memory only")
        service.flush()
        #expect(service.events.count == 1)
    }
}

private func waitUntil(timeout: Duration = .seconds(5), _ condition: () -> Bool) async {
    let deadline = ContinuousClock.now + timeout
    while !condition(), ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}
