import Foundation

public enum CompanionFrameError: Equatable, Sendable {
    case invalidLength(UInt32)
    case malformedPayload
    /// A model frame (#586) over ``ModelSchema/maximumFrameSize``: consumed whole and dropped,
    /// never cut down to fit. The receiver answers a request `tooLarge` from it.
    case oversizedModelFrame(OversizedModelFrame)

    /// Whether the stream is out of step after it: a bad length drops the decoder's buffer, so
    /// whatever follows is read from the middle of a frame. A malformed payload was consumed
    /// whole, so the next frame reads normally (#624).
    public var desyncsStream: Bool {
        if case .invalidLength = self {
            return true
        }
        return false
    }
}

/// Which model frame was over the limit (#586), so the receiver can answer it at once.
public struct OversizedModelFrame: Equatable, Sendable {
    public let requestID: UUID
    public let schema: String
    /// A `modelRequest`; otherwise a response or a cancel.
    public let isRequest: Bool

    public init(requestID: UUID, schema: String, isRequest: Bool) {
        self.requestID = requestID
        self.schema = schema
        self.isRequest = isRequest
    }

    init?(_ message: CompanionMessage) {
        switch message {
        case .modelRequest(let payload): self.init(requestID: payload.requestID, schema: payload.schema, isRequest: true)
        case .modelResponse(let payload): self.init(requestID: payload.requestID, schema: payload.schema, isRequest: false)
        case .modelCancel(let payload): self.init(requestID: payload.requestID, schema: "", isRequest: false)
        default: return nil
        }
    }

    /// The reply that ends the request at once, instead of leaving the phone to its timeout.
    public var tooLargeReply: ModelResponsePayload {
        ModelResponsePayload(requestID: requestID, schema: schema, failure: .tooLarge)
    }
}

public struct CompanionFrameBatch: Sendable {
    public let messages: [CompanionMessage]
    public let errors: [CompanionFrameError]

    public init(messages: [CompanionMessage], errors: [CompanionFrameError]) {
        self.messages = messages
        self.errors = errors
    }
}

/// Incremental length-prefixed decoder isolated from UI actors.
public actor CompanionFrameDecoder {
    public static let defaultMaximumFrameSize = 1_048_576

    private let maximumFrameSize: Int
    private var buffer = Data()

    public init(maximumFrameSize: Int = defaultMaximumFrameSize) {
        self.maximumFrameSize = maximumFrameSize
    }

    public func append(_ incoming: Data) -> CompanionFrameBatch {
        buffer.append(incoming)
        var messages: [CompanionMessage] = []
        var errors: [CompanionFrameError] = []

        while buffer.count >= 4 {
            let start = buffer.startIndex
            let length = UInt32(buffer[start]) << 24
                | UInt32(buffer[start + 1]) << 16
                | UInt32(buffer[start + 2]) << 8
                | UInt32(buffer[start + 3])

            guard length > 0, length <= maximumFrameSize else {
                errors.append(.invalidLength(length))
                buffer.removeAll(keepingCapacity: false)
                break
            }

            let frameSize = 4 + Int(length)
            guard buffer.count >= frameSize else { break }

            let payloadStart = start + 4
            let frameEnd = start + frameSize
            let payload = buffer.subdata(in: payloadStart..<frameEnd)
            buffer.removeSubrange(start..<frameEnd)

            do {
                let message = try CompanionMessage.decode(from: payload)
                if payload.count > ModelSchema.maximumFrameSize, let oversized = OversizedModelFrame(message) {
                    errors.append(.oversizedModelFrame(oversized))
                    continue
                }
                messages.append(message)
            } catch {
                errors.append(.malformedPayload)
            }
        }

        return CompanionFrameBatch(messages: messages, errors: errors)
    }

    public func reset() {
        buffer.removeAll(keepingCapacity: false)
    }
}
