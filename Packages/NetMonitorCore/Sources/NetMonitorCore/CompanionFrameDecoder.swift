import Foundation

public enum CompanionFrameError: Equatable, Sendable {
    case invalidLength(UInt32)
    case malformedPayload
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
                try messages.append(CompanionMessage.decode(from: payload))
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
