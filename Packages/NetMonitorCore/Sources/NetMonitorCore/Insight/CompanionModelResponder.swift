import Foundation
import Synchronization
#if canImport(FoundationModels)
import FoundationModels
#endif

/// The Mac's model for the companion schemas (#586): reads one input and gives the model's
/// unchecked answer. It starts the model only inside `submission.run`, so a link revoked before
/// the call never reaches the model.
public protocol CompanionModelAnswering: Sendable {
    var isAvailable: Bool { get }
    /// The answer for `input`, or nil when the model failed or `submission` refused to start it.
    func answer(_ input: ModelInput, submission: ModelSubmission) async -> ModelOutput?
}

/// The model the Mac answers with: the system model on macOS 27 and later, else none.
public enum CompanionModel {
    public static let shared: any CompanionModelAnswering = make()

    static func make() -> any CompanionModelAnswering {
        #if canImport(FoundationModels)
        if #available(iOS 27.0, macOS 27.0, *) {
            return SystemCompanionModel()
        }
        #endif
        return UnavailableCompanionModel()
    }
}

/// Where the model can't run: the Mac advertises no schema.
public struct UnavailableCompanionModel: CompanionModelAnswering {
    public init() {}
    public var isAvailable: Bool { false }
    public func answer(_ input: ModelInput, submission: ModelSubmission) async -> ModelOutput? { nil }
}

#if canImport(FoundationModels)
/// The system model, through the same instructions and typed answers the local parsers use.
@available(iOS 27.0, macOS 27.0, *)
struct SystemCompanionModel: CompanionModelAnswering {
    var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

    func answer(_ input: ModelInput, submission: ModelSubmission) async -> ModelOutput? {
        switch input {
        case .rules(let text):
            await SystemRuleIntentParser.raw(for: text, submission: submission).map(ModelOutput.rules)
        case .symptoms(let text):
            await SystemSymptomClassifier.raw(for: text, submission: submission).map(ModelOutput.symptoms)
        case .identity(let projection):
            await SystemInsightService.identity(for: projection, submission: submission).map(ModelOutput.identity)
        }
    }
}
#endif

/// The Mac's side of `modelRequest` (#586): answers a paired phone's typed rule or symptom with
/// the Mac's model. The answer goes back unchecked, because the phone checks it against what the
/// user typed, as it checks its own model's.
///
/// - Admission: `ModelAdmission` gives the request the one companion slot, or the reply is
///   `busy` (interactive work on the Mac, another companion request, or the budget spent). A
///   Mac scan is `busy` too.
/// - Authorisation: checked at entry, after each suspension, and at the model call itself
///   (`ModelSubmission`), together with the Mac's "Answer model requests from iPhone" setting.
/// - Cancellation: when the request's task is cancelled (a `modelCancel`, or the link closing),
///   the reply is nil (nothing is sent) and the model is cancelled. The slot stays held until the
///   model really returns.
/// - Timeout: after `timeout` the reply is `timeout` and the model is cancelled; again the slot
///   is held until it returns.
///
/// Inputs carry what the user typed, so nothing here is logged.
public struct CompanionModelResponder: Sendable {
    public static let defaultTimeout: Duration = .seconds(10)

    private let model: any CompanionModelAnswering
    private let admission: ModelAdmission
    private let timeout: Duration
    private let isAllowed: @Sendable () -> Bool
    private let isScanning: @Sendable () async -> Bool
    private let beforeSubmission: (@Sendable () async -> Void)?

    public init(
        model: any CompanionModelAnswering = CompanionModel.shared,
        admission: ModelAdmission = .shared,
        timeout: Duration = defaultTimeout,
        isAllowed: @escaping @Sendable () -> Bool = { true },
        isScanning: @escaping @Sendable () async -> Bool = { false }
    ) {
        self.init(model: model, admission: admission, timeout: timeout, isAllowed: isAllowed, isScanning: isScanning, beforeSubmission: nil)
    }

    /// - Parameter beforeSubmission: tests only, see ``ModelSubmission``.
    init(
        model: any CompanionModelAnswering,
        admission: ModelAdmission,
        timeout: Duration = defaultTimeout,
        isAllowed: @escaping @Sendable () -> Bool = { true },
        isScanning: @escaping @Sendable () async -> Bool = { false },
        beforeSubmission: (@Sendable () async -> Void)?
    ) {
        self.model = model
        self.admission = admission
        self.timeout = timeout
        self.isAllowed = isAllowed
        self.isScanning = isScanning
        self.beforeSubmission = beforeSubmission
    }

    /// The schemas a Mac heartbeat lists: every one while the model can be used and the user
    /// lets the Mac answer. Unlike `insight.v1`, they stay listed during a scan, which is
    /// answered `busy`, so a phone's field doesn't come and go with every scan.
    public func capabilities(allowed: Bool) -> [String] {
        allowed && model.isAvailable ? ModelSchema.allCases.map(\.rawValue) : []
    }

    /// The reply to `payload`, or nil when the request was cancelled: nothing is sent then.
    public func respond(to payload: ModelRequestPayload, authorization: CompanionAuthorization) async -> ModelResponsePayload? {
        let id = payload.requestID
        let schema = payload.schema
        func failure(_ reason: InsightFailureReason) -> ModelResponsePayload? {
            Task.isCancelled ? nil : ModelResponsePayload(requestID: id, schema: schema, failure: reason)
        }
        guard authorization.isCurrent() else { return failure(.unavailable) }
        guard let input = payload.input else { return failure(.refused) }
        guard input.isWithinLimits else { return failure(.tooLarge) }
        guard isAllowed(), model.isAvailable else { return failure(.unavailable) }
        let scanning = await isScanning()
        guard authorization.isCurrent() else { return failure(.unavailable) }
        // Identity is a phone's background pass: its own, lower-priority budget.
        let priority: ModelAdmission.Priority = input.schema == .identity ? .background : .interactive
        guard !scanning, let ticket = admission.admitCompanion(priority) else { return failure(.busy) }

        let isAllowed = isAllowed
        let started = Mutex(false)
        let submission = ModelSubmission(
            authorization: authorization, isAllowed: isAllowed, beforeCall: beforeSubmission, didStart: { started.withLock { $0 = true } }
        )
        // Started inside the link's lock and registered with it: a close or revoke from here on
        // cancels the work, and with it the model call.
        guard let work = admission.withTicket(ticket, {
            authorization.start { [model, admission] () -> ModelOutput? in
                defer {
                    // A request the model never ran for (cancelled, revoked, turned off) spends no
                    // budget (#642 review). Released only when the model has returned.
                    if !started.withLock({ $0 }) {
                        admission.refund(ticket)
                    }
                    admission.release(ticket)
                }
                return await model.answer(input, submission: submission)
            }
        }) else {
            admission.release(ticket)
            return failure(.unavailable)
        }
        switch await Self.first(of: work, timeout: timeout) {
        case .cancelled:
            return nil
        case .timedOut:
            work.cancel()
            return failure(.timeout)
        case .answered(let output):
            // The owner may have turned answering off while the model worked: no answer then.
            guard authorization.isCurrent(), isAllowed() else { return failure(.unavailable) }
            guard let output, output.schema == input.schema else { return failure(.refused) }
            return output.isWithinLimits ? ModelResponsePayload(requestID: id, output: output) : failure(.refused)
        }
    }

    // MARK: - Waiting

    enum Outcome: Sendable {
        case answered(ModelOutput?)
        case timedOut
        case cancelled
    }

    /// The first of: the work's answer, `timeout`, or the caller's cancellation (which cancels
    /// the work). Returns at once in each case, even if the work ignores cancellation.
    static func first(of work: Task<ModelOutput?, Never>, timeout: Duration) async -> Outcome {
        let race = Race()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                race.wait(with: continuation)
                let waiter = Task { await race.finish(.answered(work.value)) }
                let timer = Task {
                    try? await Task.sleep(for: timeout)
                    race.finish(.timedOut)
                }
                race.onFinish {
                    waiter.cancel()
                    timer.cancel()
                }
            }
        } onCancel: {
            work.cancel()
            race.finish(.cancelled)
        }
    }

    /// One outcome, delivered once, whether it comes before or after the wait starts.
    private final class Race: Sendable {
        private struct State {
            var continuation: CheckedContinuation<Outcome, Never>?
            var outcome: Outcome?
            var cleanup: (@Sendable () -> Void)?
        }

        private let state = Mutex(State())

        func wait(with continuation: CheckedContinuation<Outcome, Never>) {
            let early: Outcome? = state.withLock { state in
                guard let outcome = state.outcome else {
                    state.continuation = continuation
                    return nil
                }
                return outcome
            }
            if let early {
                continuation.resume(returning: early)
            }
        }

        func onFinish(_ cleanup: @escaping @Sendable () -> Void) {
            let finished = state.withLock { state in
                guard state.outcome == nil else { return true }
                state.cleanup = cleanup
                return false
            }
            if finished {
                cleanup()
            }
        }

        func finish(_ outcome: Outcome) {
            let (continuation, cleanup): (CheckedContinuation<Outcome, Never>?, (@Sendable () -> Void)?) = state.withLock { state in
                guard state.outcome == nil else { return (nil, nil) }
                state.outcome = outcome
                defer {
                    state.continuation = nil
                    state.cleanup = nil
                }
                return (state.continuation, state.cleanup)
            }
            continuation?.resume(returning: outcome)
            cleanup?()
        }
    }
}
