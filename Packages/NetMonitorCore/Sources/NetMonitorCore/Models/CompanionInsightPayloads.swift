import Foundation

// MARK: - Insight over the companion link (#457)

/// iPhone → Mac: an `InsightRequest` for the Mac's model to word. Only the app-built request
/// travels: the Mac takes the instructions from `kind`, never from the wire.
public struct InsightRequestPayload: Codable, Sendable, Equatable {
    public let requestID: UUID
    /// The request kind's wire name, kept as a string so a kind this build doesn't know
    /// still decodes and gets a failure reply instead of a dropped frame.
    public let kind: String
    public let subject: String
    public let facts: [String]
    public let observations: [String]

    public init(requestID: UUID, request: InsightRequest) {
        self.requestID = requestID
        kind = request.kind.wireName
        subject = request.subject
        facts = request.facts
        observations = request.observations
    }

    /// The request to answer, or nil when `kind` is one this build doesn't know.
    public var request: InsightRequest? {
        InsightRequest.Kind(wireName: kind).map {
            InsightRequest(subject: subject, facts: facts, observations: observations, kind: $0)
        }
    }

    /// Largest encoded request the phone sends, far below the 1 MiB frame cap: a frame over
    /// the cap clears the receiver's buffer, and the model's context only holds a few
    /// thousand tokens anyway.
    public static let maximumEncodedSize = 64 * 1024
}

/// Why the Mac sent no answer.
public enum InsightFailureReason: String, Codable, Sendable, CaseIterable {
    /// The Mac's model can't be used now, or the Mac doesn't answer iPhone requests.
    case unavailable
    /// The model failed, or its answer didn't pass the app's checks.
    case refused
    /// The model took too long.
    case timeout
    /// The request was over `InsightRequestPayload.maximumEncodedSize`.
    case tooLarge
    /// The Mac is scanning or already answering another request.
    case busy
}

/// Mac → iPhone: the whole answer to one `insightRequest`, or why there is none.
public struct InsightResponsePayload: Codable, Sendable, Equatable {
    public let requestID: UUID
    /// The checked answer; nil when the request failed.
    public let answer: String?
    /// An `InsightFailureReason` raw value, kept as a string so a newer reason still decodes.
    public let failure: String?

    public init(requestID: UUID, answer: String) {
        self.requestID = requestID
        self.answer = answer
        failure = nil
    }

    public init(requestID: UUID, failure: InsightFailureReason) {
        self.requestID = requestID
        answer = nil
        self.failure = failure.rawValue
    }

    /// Why there is no answer; a reason this build doesn't know reads as `.refused`.
    public var failureReason: InsightFailureReason? {
        guard answer == nil else { return nil }
        return failure.flatMap(InsightFailureReason.init(rawValue:)) ?? .refused
    }
}

extension InsightRequest.Kind {
    /// The kind's name on the companion wire.
    public var wireName: String {
        switch self {
        case .explanation: "explanation"
        case .summary: "summary"
        case .notification: "notification"
        case .advice: "advice"
        }
    }

    public init?(wireName: String) {
        switch wireName {
        case "explanation": self = .explanation
        case "summary": self = .summary
        case "notification": self = .notification
        case "advice": self = .advice
        default: return nil
        }
    }
}
