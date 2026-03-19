import Testing
import Foundation
import SwiftData
import NetMonitorCore
@testable import NetMonitor_macOS

/// Tests that verify MonitoringSession surfaces SwiftData save errors to the user
/// via the `errorMessage` property rather than silently logging them.
///
/// The three save sites under test (post-session-start, post-session-stop,
/// post-measurement) cannot be forced to fail through a real in-memory store
/// because SwiftData's in-memory backend does not surface arbitrary save errors.
///
/// Instead, these tests validate the observable `errorMessage` state machine
/// for the paths we can control:
///  - fetch failures (real path: errors are surfaced)
///  - successful saves leave errorMessage nil
///  - stop after start leaves session in consistent state
///
/// For full save-failure injection, an `ErrorInjectingModelContext` subclass
/// would be needed, which SwiftData does not currently expose. The tests below
/// document intent and provide regression coverage for the state machine logic
/// that was fixed in this commit (errorMessage was previously never set on save
/// failures).
@Suite(.serialized)
@MainActor
struct MonitoringSessionSaveErrorTests {

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> (ModelContainer, ModelContext) {
        let schema = Schema([
            NetworkTarget.self,
            SessionRecord.self,
            TargetMeasurement.self
        ])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [config])
        return (container, container.mainContext)
    }

    /// Stub service that immediately returns a successful measurement so
    /// MonitoringSession exercises the updateMeasurement save path.
    private actor StubMonitorService: NetworkMonitorService {
        func check(request: TargetCheckRequest) async throws -> MeasurementResult {
            MeasurementResult(latency: 10.0, isReachable: true, errorMessage: nil)
        }
    }

    private func makeSession(context: ModelContext) -> MonitoringSession {
        MonitoringSession(
            modelContext: context,
            anyHTTPService: StubMonitorService(),
            anyICMPService: StubMonitorService(),
            anyTCPService: StubMonitorService()
        )
    }

    // MARK: - Initial state

    @Test("errorMessage is nil before any monitoring starts")
    func errorMessageNilInitially() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container
        let session = makeSession(context: context)
        #expect(session.errorMessage == nil)
        #expect(session.isMonitoring == false)
    }

    // MARK: - No targets → errorMessage set

    @Test("startMonitoring with no enabled targets sets errorMessage")
    func startMonitoringWithNoTargetsSetsErrorMessage() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container
        let session = makeSession(context: context)

        // Store is empty — no NetworkTargets exist.
        session.startMonitoring()

        #expect(session.isMonitoring == false)
        #expect(session.errorMessage != nil)
        #expect(session.errorMessage?.isEmpty == false)
    }

    @Test("errorMessage after no-target start contains useful description")
    func errorMessageContentAfterNoTargetStart() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container
        let session = makeSession(context: context)

        session.startMonitoring()

        // Must say something about targets so the user understands what to do.
        let msg = session.errorMessage ?? ""
        #expect(msg.lowercased().contains("target") || msg.lowercased().contains("enabled"),
                "errorMessage should mention targets or enabled state, got: \(msg)")
    }

    // MARK: - startMonitoring clears previous errorMessage

    @Test("startMonitoring clears a pre-existing errorMessage before processing")
    func startMonitoringClearsPreviousError() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container
        let session = makeSession(context: context)

        // Force an error first
        session.startMonitoring()
        let firstError = session.errorMessage
        #expect(firstError != nil)

        // Insert a target, start again — errorMessage should clear during the
        // second start attempt even if it then sets a new one.
        let target = NetworkTarget(
            name: "Test",
            host: "example.com",
            targetProtocol: .http,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        session.startMonitoring()
        // Either monitoring started (no message) or a different error was set.
        // Either way, the *old* message must not still be present unchanged.
        // (startMonitoring always sets errorMessage = nil at entry)
        let secondError = session.errorMessage
        // If monitoring succeeded, errorMessage is nil.
        // If it failed for another reason, it's a new message.
        // We can't distinguish without controlling the save, so we verify
        // that the session processed the second call (isMonitoring changed).
        #expect(session.isMonitoring == true || secondError != firstError)

        session.stopMonitoring()
    }

    // MARK: - Successful start/stop cycle

    @Test("startMonitoring with a valid target leaves errorMessage nil")
    func successfulStartLeavesErrorMessageNil() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container
        let session = makeSession(context: context)

        let target = NetworkTarget(
            name: "Test",
            host: "example.com",
            targetProtocol: .http,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        session.startMonitoring()
        #expect(session.isMonitoring == true)
        #expect(session.errorMessage == nil)

        session.stopMonitoring()
        #expect(session.isMonitoring == false)
    }

    @Test("stopMonitoring after successful start leaves errorMessage nil")
    func stopAfterSuccessfulStartErrorMessageNil() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container
        let session = makeSession(context: context)

        let target = NetworkTarget(
            name: "Test",
            host: "example.com",
            targetProtocol: .http,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        session.startMonitoring()
        session.stopMonitoring()

        // In-memory save succeeds, so errorMessage must remain nil after stop.
        #expect(session.errorMessage == nil)
        #expect(session.isMonitoring == false)
    }

    // MARK: - startTime set on successful start

    @Test("startMonitoring sets startTime")
    func startMonitoringSetStartTime() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container
        let session = makeSession(context: context)

        let target = NetworkTarget(
            name: "Test",
            host: "example.com",
            targetProtocol: .http,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        let before = Date()
        session.startMonitoring()
        let after = Date()

        if let startTime = session.startTime {
            #expect(startTime >= before)
            #expect(startTime <= after)
        } else {
            Issue.record("startTime should be set after startMonitoring()")
        }

        session.stopMonitoring()
    }

    // MARK: - Double-start guard

    @Test("Calling startMonitoring twice does not change isMonitoring or errorMessage")
    func doubleStartIsIdempotent() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container
        let session = makeSession(context: context)

        let target = NetworkTarget(
            name: "Test",
            host: "example.com",
            targetProtocol: .http,
            isEnabled: true
        )
        context.insert(target)
        try context.save()

        session.startMonitoring()
        #expect(session.isMonitoring == true)
        let errorAfterFirst = session.errorMessage

        // Second call should be a no-op (guard !isMonitoring)
        session.startMonitoring()
        #expect(session.isMonitoring == true)
        #expect(session.errorMessage == errorAfterFirst)

        session.stopMonitoring()
    }

    // MARK: - Disabled targets not included

    @Test("Disabled-only targets treated same as no targets: errorMessage is set")
    func disabledOnlyTargetsSetsErrorMessage() throws {
        let (container, context) = try makeInMemoryContainer()
        _ = container
        let session = makeSession(context: context)

        let disabledTarget = NetworkTarget(
            name: "Disabled",
            host: "example.com",
            targetProtocol: .http,
            isEnabled: false
        )
        context.insert(disabledTarget)
        try context.save()

        session.startMonitoring()

        #expect(session.isMonitoring == false)
        #expect(session.errorMessage != nil)
    }
}
