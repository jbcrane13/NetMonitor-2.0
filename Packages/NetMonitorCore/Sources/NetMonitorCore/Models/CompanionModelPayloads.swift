import Foundation

// MARK: - Model requests over the companion link (#586)

/// What a `modelRequest` asks the Mac's model to read. Each schema is its own heartbeat
/// capability, and the Mac takes the instructions and the answer's shape from the schema,
/// never from the wire.
public enum ModelSchema: String, Sendable, CaseIterable {
    /// A rule typed in plain English (#450): text in, a ``RuleIntentRaw`` out.
    case rules = "rules.v1"
    /// A symptom typed in the troubleshooter (#451): text in, a ``SymptomIntentRaw`` out.
    case symptoms = "symptoms.v1"

    /// The longest text a request may carry; a longer one isn't sent, never cut.
    public static let textLimit = 300
    /// The longest text field in an answer; a longer one fails the answer, never cut.
    public static let fieldLimit = 120
    /// The longest `kind` in an answer.
    public static let kindLimit = 32
    /// The largest model frame either side accepts (`CompanionFrameDecoder`): a request or an
    /// answer is a few hundred bytes, so anything near this is not one.
    public static let maximumFrameSize = 16 * 1024
}

/// The input a schema carries.
public enum ModelInput: Sendable, Equatable {
    case rules(text: String)
    case symptoms(text: String)

    public var schema: ModelSchema {
        switch self {
        case .rules: .rules
        case .symptoms: .symptoms
        }
    }

    /// The typed text.
    public var text: String {
        switch self {
        case .rules(let text), .symptoms(let text): text
        }
    }

    /// Whether the text is non-empty and within ``ModelSchema/textLimit``.
    public var isWithinLimits: Bool { !text.isEmpty && text.count <= ModelSchema.textLimit }
}

/// The Mac model's unchecked answer for a schema. The phone checks it as it checks its own
/// model's (`RuleIntentRaw.intent(for:)`, `SymptomIntentRaw.intent(for:)`).
public enum ModelOutput: Sendable, Equatable {
    case rules(RuleIntentRaw)
    case symptoms(SymptomIntentRaw)

    public var schema: ModelSchema {
        switch self {
        case .rules: .rules
        case .symptoms: .symptoms
        }
    }

    public var isWithinLimits: Bool {
        switch self {
        case .rules(let raw): raw.isWithinLimits
        case .symptoms(let raw): raw.isWithinLimits
        }
    }
}

/// iPhone → Mac: read `input` with the Mac's model. Sent only to a Mac whose latest heartbeat
/// lists the schema.
public struct ModelRequestPayload: Codable, Sendable, Equatable {
    public let requestID: UUID
    /// The schema's wire name, kept as a string so a schema this build doesn't know still
    /// decodes and is answered `refused`.
    public let schema: String
    /// Nil when the schema is unknown or its input didn't decode: answered `refused`.
    public let input: ModelInput?

    public init(requestID: UUID, input: ModelInput) {
        self.requestID = requestID
        schema = input.schema.rawValue
        self.input = input
    }

    private enum CodingKeys: String, CodingKey {
        case requestID, schema, input
    }

    private struct TextInput: Codable {
        let text: String
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        schema = try container.decode(String.self, forKey: .schema)
        // The envelope first: a known schema whose input is malformed is refused, not dropped.
        let text = try? container.decode(TextInput.self, forKey: .input).text
        switch (ModelSchema(rawValue: schema), text) {
        case (.rules?, let text?): input = .rules(text: text)
        case (.symptoms?, let text?): input = .symptoms(text: text)
        default: input = nil
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(schema, forKey: .schema)
        if let input {
            try container.encode(TextInput(text: input.text), forKey: .input)
        }
    }
}

/// Mac → iPhone: the whole answer to one `modelRequest`, or why there is none. Never sent
/// unprompted, and never after a `modelCancel`.
public struct ModelResponsePayload: Codable, Sendable, Equatable {
    public let requestID: UUID
    public let schema: String
    /// The model's unchecked answer; nil with a failure, or when it didn't decode.
    public let output: ModelOutput?
    /// An `InsightFailureReason` raw value.
    public let failure: String?
    /// The frame carried an `output` this build couldn't read for the schema.
    private let outputIsMalformed: Bool

    public init(requestID: UUID, output: ModelOutput) {
        self.requestID = requestID
        schema = output.schema.rawValue
        self.output = output
        failure = nil
        outputIsMalformed = false
    }

    public init(requestID: UUID, schema: String, failure: InsightFailureReason) {
        self.requestID = requestID
        self.schema = schema
        output = nil
        self.failure = failure.rawValue
        outputIsMalformed = false
    }

    /// What the phone may use: the answer, the failure, or nil when the reply breaks the
    /// rules. That covers a schema other than `expected`, both or neither of output and
    /// failure, an output it couldn't read, and a field over its limit.
    public func result(expecting expected: ModelSchema) -> ModelResult? {
        guard schema == expected.rawValue, !outputIsMalformed else { return nil }
        switch (output, failure) {
        case (let output?, nil):
            return output.schema == expected && output.isWithinLimits ? .output(output) : nil
        case (nil, let failure?):
            return .failure(InsightFailureReason(rawValue: failure) ?? .refused)
        default:
            return nil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case requestID, schema, output, failure
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        requestID = try container.decode(UUID.self, forKey: .requestID)
        schema = try container.decode(String.self, forKey: .schema)
        failure = try container.decodeIfPresent(String.self, forKey: .failure)
        guard container.contains(.output) else {
            output = nil
            outputIsMalformed = false
            return
        }
        switch ModelSchema(rawValue: schema) {
        case .rules?:
            output = (try? container.decode(RuleIntentRaw.self, forKey: .output)).map(ModelOutput.rules)
        case .symptoms?:
            output = (try? container.decode(SymptomIntentRaw.self, forKey: .output)).map(ModelOutput.symptoms)
        case nil:
            output = nil
        }
        outputIsMalformed = output == nil
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(requestID, forKey: .requestID)
        try container.encode(schema, forKey: .schema)
        try container.encodeIfPresent(failure, forKey: .failure)
        switch output {
        case .rules(let raw)?: try container.encode(raw, forKey: .output)
        case .symptoms(let raw)?: try container.encode(raw, forKey: .output)
        case nil: break
        }
    }
}

/// What a valid `modelResponse` says.
public enum ModelResult: Sendable, Equatable {
    case output(ModelOutput)
    case failure(InsightFailureReason)
}

/// iPhone → Mac: the phone gave up on a request (its timeout, or the user left). The Mac
/// stops it and sends nothing for it.
public struct ModelCancelPayload: Codable, Sendable, Equatable {
    public let requestID: UUID

    public init(requestID: UUID) {
        self.requestID = requestID
    }
}
