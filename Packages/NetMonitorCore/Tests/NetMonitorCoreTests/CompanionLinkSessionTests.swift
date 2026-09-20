import Foundation
import Testing
@testable import NetMonitorCore

// MARK: - Helpers

private let referenceInstant = Date(timeIntervalSinceReferenceDate: 1_000_000.0)

// MARK: - Liveness

struct CompanionLinkSessionLivenessTests {
    @Test("isAlive is false before anything has been received")
    func isAliveFalseInitially() {
        let session = CompanionLinkSession()
        #expect(session.isAlive(now: referenceInstant) == false)
    }

    @Test("isAlive is true just before the staleness threshold")
    func isAliveTrueJustBeforeThreshold() {
        var session = CompanionLinkSession(heartbeatInterval: 15, missedBeatsBeforeStale: 3)
        session.recordReceived(at: referenceInstant)
        // Threshold is 45s; check 1ms before it.
        let almostStale = referenceInstant.addingTimeInterval(45 - 0.001)
        #expect(session.isAlive(now: almostStale) == true)
    }

    @Test("isAlive is false at and beyond the staleness threshold")
    func isAliveFalseAtThreshold() {
        var session = CompanionLinkSession(heartbeatInterval: 15, missedBeatsBeforeStale: 3)
        session.recordReceived(at: referenceInstant)
        let atThreshold = referenceInstant.addingTimeInterval(45)
        #expect(session.isAlive(now: atThreshold) == false)

        let pastThreshold = referenceInstant.addingTimeInterval(90)
        #expect(session.isAlive(now: pastThreshold) == false)
    }

    @Test("isAlive respects custom heartbeatInterval and missedBeatsBeforeStale")
    func isAliveHonorsCustomConfiguration() {
        var session = CompanionLinkSession(heartbeatInterval: 5, missedBeatsBeforeStale: 2)
        session.recordReceived(at: referenceInstant)
        // Threshold is 10s.
        #expect(session.isAlive(now: referenceInstant.addingTimeInterval(9)) == true)
        #expect(session.isAlive(now: referenceInstant.addingTimeInterval(10)) == false)
    }

    @Test("recordReceived on any message updates lastReceived, not only heartbeats")
    func recordReceivedUpdatesLastReceived() {
        var session = CompanionLinkSession()
        #expect(session.lastReceived == nil)
        session.recordReceived(at: referenceInstant)
        #expect(session.lastReceived == referenceInstant)

        let later = referenceInstant.addingTimeInterval(5)
        session.recordReceived(at: later)
        #expect(session.lastReceived == later)
    }
}

// MARK: - Reconnect

struct CompanionLinkSessionReconnectTests {
    @Test("reconnectAttempt starts at zero")
    func reconnectAttemptStartsAtZero() {
        let session = CompanionLinkSession()
        #expect(session.reconnectAttempt == 0)
    }

    @Test("nextReconnectDelay increments reconnectAttempt")
    func nextReconnectDelayIncrementsAttempt() {
        var session = CompanionLinkSession()
        _ = session.nextReconnectDelay(jitterFraction: 0)
        #expect(session.reconnectAttempt == 1)
        _ = session.nextReconnectDelay(jitterFraction: 0)
        #expect(session.reconnectAttempt == 2)
        _ = session.nextReconnectDelay(jitterFraction: 0)
        #expect(session.reconnectAttempt == 3)
    }

    @Test("nextReconnectDelay matches the static reconnectDelay formula")
    func nextReconnectDelayMatchesStaticFormula() {
        var session = CompanionLinkSession()
        for attempt in 1...10 {
            let jitter = Double(attempt) / 10.0
            let expected = CompanionLinkSession.reconnectDelay(attempt: attempt, jitterFraction: jitter)
            let actual = session.nextReconnectDelay(jitterFraction: jitter)
            #expect(actual == expected)
        }
    }

    @Test("recordConnected resets reconnectAttempt to zero")
    func recordConnectedResetsAttempt() {
        var session = CompanionLinkSession()
        _ = session.nextReconnectDelay(jitterFraction: 0)
        _ = session.nextReconnectDelay(jitterFraction: 0)
        #expect(session.reconnectAttempt == 2)

        session.recordConnected(at: referenceInstant)
        #expect(session.reconnectAttempt == 0)
    }

    @Test("recordConnected marks the session alive at that instant")
    func recordConnectedMarksAlive() {
        var session = CompanionLinkSession()
        session.recordConnected(at: referenceInstant)
        #expect(session.isAlive(now: referenceInstant) == true)
    }

    @Test("reset clears reconnectAttempt and lastReceived")
    func resetClearsState() {
        var session = CompanionLinkSession()
        session.recordReceived(at: referenceInstant)
        _ = session.nextReconnectDelay(jitterFraction: 0)
        _ = session.nextReconnectDelay(jitterFraction: 0)

        session.reset()

        #expect(session.reconnectAttempt == 0)
        #expect(session.lastReceived == nil)
        #expect(session.isAlive(now: referenceInstant) == false)
    }
}

// MARK: - Backoff formula parity

struct CompanionLinkSessionBackoffFormulaTests {
    @Test(
        "reconnectDelay matches the original MacConnectionService formula across attempts and jitter",
        arguments: [
            (attempt: 1, jitterFraction: 0.0, expected: 1.0),
            (attempt: 2, jitterFraction: 0.0, expected: 2.0),
            (attempt: 3, jitterFraction: 1.0, expected: 5.0),
            (attempt: 20, jitterFraction: 1.0, expected: 60.0),
            (attempt: 0, jitterFraction: 0.0, expected: 1.0),
            (attempt: 1, jitterFraction: 0.5, expected: 1.125),
            (attempt: 4, jitterFraction: 0.5, expected: 9.0),
            (attempt: 7, jitterFraction: 0.0, expected: 60.0)
        ]
    )
    func reconnectDelayMatchesOriginalFormula(attempt: Int, jitterFraction: Double, expected: Double) {
        let actual = CompanionLinkSession.reconnectDelay(attempt: attempt, jitterFraction: jitterFraction)
        #expect(abs(actual - expected) < 0.0001)
    }

    @Test("reconnectDelay clamps jitterFraction outside 0...1")
    func reconnectDelayClampsJitterFraction() {
        let belowRange = CompanionLinkSession.reconnectDelay(attempt: 2, jitterFraction: -5)
        let aboveRange = CompanionLinkSession.reconnectDelay(attempt: 2, jitterFraction: 5)
        #expect(belowRange == 2)
        #expect(aboveRange == CompanionLinkSession.reconnectDelay(attempt: 2, jitterFraction: 1))
    }
}
