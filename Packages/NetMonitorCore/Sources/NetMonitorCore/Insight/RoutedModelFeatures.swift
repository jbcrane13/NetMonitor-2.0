import Foundation
import Synchronization

/// The Mac route for one schema (#586): whether a typed request may go to the connected Mac, and
/// whether the user must be asked first. Requests go only while the Mac's latest heartbeat lists
/// the schema and the user agreed under `MacInsightConsent.readingDefaultsKey`.
public struct MacModelRoute: Sendable {
    public let mac: CompanionModelClient
    /// The user's answer to "Use your Mac to read what you type?".
    public let consent: MacInsightConsent
    public let schema: ModelSchema

    public init(mac: CompanionModelClient, consent: MacInsightConsent, schema: ModelSchema) {
        self.mac = mac
        self.consent = consent
        self.schema = schema
    }

    /// Whether the Mac could read it, and whether the user has agreed.
    public var availability: InsightAvailability {
        guard mac.offers(schema) else { return .unavailable }
        switch consent.decision {
        case true?: return .available
        case nil: return .needsConsent
        case false?: return .unavailable
        }
    }

    /// The Mac's unchecked answer, or nil. Everything runs under the consent generation it began
    /// with: nothing is sent, and no answer is used, once the user withdrew it (even if they agreed
    /// again meanwhile), and withdrawing ends the request at once.
    func request(_ input: ModelInput) async -> ModelOutput? {
        guard case .output(let output) = await result(input) else { return nil }
        return output
    }

    /// As `request`, with why there's no answer. `alsoWhile` joins the consent in the condition the
    /// connection checks at the send itself (for identity, that the phone isn't scanning).
    func result(_ input: ModelInput, alsoWhile extra: @escaping @Sendable () -> Bool = { true }) async -> ModelClientResult {
        guard let scope = consent.currentGeneration else { return .unavailable }
        let mac = mac
        let isCurrent = scope.isCurrent
        let work = Task { await mac.request(input, while: { isCurrent() && extra() }) }
        let remove = scope.onWithdrawal { work.cancel() }
        defer { remove() }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        return scope.isCurrent() ? result : .unavailable
    }
}

/// The iPhone's rule parser (#586): the local model when it's available, else the connected
/// Mac's through `rules.v1`. The Mac's answer is checked here, against what the user typed,
/// by the same `RuleIntentRaw.intent(for:)` the local model's answer goes through.
public struct RoutedRuleIntentParser: RuleIntentParsing {
    public let local: any RuleIntentParsing
    public let route: MacModelRoute

    public init(local: any RuleIntentParsing, mac: CompanionModelClient, consent: MacInsightConsent) {
        self.local = local
        route = MacModelRoute(mac: mac, consent: consent, schema: .rules)
    }

    /// The field shows while the local model runs, or the Mac could read it and the user hasn't
    /// said no: with no answer yet, the first submit asks.
    public var isAvailable: Bool { availability != .unavailable }

    public var availability: InsightAvailability {
        local.isAvailable ? .available : route.availability
    }

    public var answerSource: InsightSource { local.isAvailable ? .device : .mac }

    public var macConsent: MacInsightConsent? { local.isAvailable ? nil : route.consent }

    public func parse(_ text: String) async -> RuleIntent? {
        if local.isAvailable {
            return await local.parse(text)
        }
        guard case .rules(let raw)? = await route.request(.rules(text: text)) else { return nil }
        return raw.intent(for: text)
    }
}

/// The iPhone's symptom classifier (#586): the local model when it's available, else the
/// connected Mac's through `symptoms.v1`, checked here by `SymptomIntentRaw.intent(for:)`.
public struct RoutedSymptomClassifier: SymptomClassifierProtocol {
    public let local: any SymptomClassifierProtocol
    public let route: MacModelRoute

    public init(local: any SymptomClassifierProtocol, mac: CompanionModelClient, consent: MacInsightConsent) {
        self.local = local
        route = MacModelRoute(mac: mac, consent: consent, schema: .symptoms)
    }

    public var isAvailable: Bool { availability != .unavailable }

    public var availability: InsightAvailability {
        local.isAvailable ? .available : route.availability
    }

    public var answerSource: InsightSource { local.isAvailable ? .device : .mac }

    public var macConsent: MacInsightConsent? { local.isAvailable ? nil : route.consent }

    public func classify(_ symptom: String) async -> SymptomIntent? {
        if local.isAvailable {
            return await local.classify(symptom)
        }
        guard case .symptoms(let raw)? = await route.request(.symptoms(text: symptom)) else { return nil }
        return raw.intent(for: symptom)
    }
}

/// The iPhone's identity suggestions (#586): the local model when it's available, else the
/// connected Mac's through `identity.v1`. The Mac reads the same bounded evidence the local model
/// would (`DeviceEvidence.projection`); its answer comes back marked `.mac` and goes through the
/// same checks in `DeviceSuggester`.
///
/// Suggestions run in the background, so this never asks the user: the Mac is used only once they
/// already agreed to "Let your Mac read what you type?", whose wording covers device evidence.
/// Explanations stay on the local model; `RoutedInsightService` routes those.
public struct RoutedIdentityService: InsightServiceProtocol {
    /// How long the Mac isn't asked after it answered `busy` (#642 review): about one inference.
    public static let busyRetryAfter: Duration = .seconds(15)
    /// How long the Mac isn't asked after a link-level failure: no reply, a failed send, its model
    /// unavailable.
    public static let linkRetryAfter: Duration = .seconds(30)
    /// How long a `busy` can be the Mac still finishing a request this phone gave up on: its own
    /// timeout and a margin. Such a `busy` is retried, every `retryInterval`, not backed off.
    public static let abandonedWindow: Duration = CompanionModelResponder.defaultTimeout + .seconds(3)

    public let local: any InsightServiceProtocol
    public let route: MacModelRoute
    private let state: RetryState
    private let retryInterval: Duration
    /// Whether the phone is scanning now, safe to read from any thread: never ask during it (#447).
    private let isPhoneScanning: @Sendable () -> Bool

    public init(
        local: any InsightServiceProtocol,
        mac: CompanionModelClient,
        consent: MacInsightConsent,
        retryInterval: Duration = .seconds(2),
        isPhoneScanning: @escaping @Sendable () -> Bool = { false },
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now }
    ) {
        self.local = local
        route = MacModelRoute(mac: mac, consent: consent, schema: .identity)
        state = RetryState(now: now)
        self.retryInterval = retryInterval
        self.isPhoneScanning = isPhoneScanning
    }

    /// The local model, or a Mac offering identity once the user has said yes and not backing off
    /// after a busy or link failure; never "ask first". `DeviceSuggester` stops its pass, without
    /// recording, when this turns false under it.
    public var isAvailable: Bool {
        local.isAvailable || (route.availability == .available && !state.isBackingOff && !isPhoneScanning())
    }

    /// Explanations aren't this service's job: `RoutedInsightService` routes them. It forwards to
    /// the local model only because `DeviceSuggester` takes an `InsightServiceProtocol`, which
    /// mustn't change (#447).
    public func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        local.explain(request)
    }

    /// The Mac's suggestion, or nil:
    /// - refused or too large: nil with the service still available, so `DeviceSuggester` records it
    ///   against that device's evidence, like a local failure;
    /// - timed out: for now, like a link failure;
    /// - busy: back off `busyRetryAfter`, unless it follows this phone's own cancel, when the Mac is
    ///   still finishing the abandoned request: then it is retried until `abandonedWindow` passes;
    /// - a link failure or a timeout while the Mac still offers identity: back off `linkRetryAfter`;
    /// - consent withdrawn, a disconnect, the phone's scan, or the caller's cancel: no back-off.
    public func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        if local.isAvailable {
            return await local.suggestIdentity(evidence)
        }
        let isPhoneScanning = isPhoneScanning
        while route.availability == .available, !state.isBackingOff, !isPhoneScanning() {
            // The scan is checked again by the connection, in the same step as the send.
            let result = await route.result(.identity(evidence.projection), alsoWhile: { !isPhoneScanning() })
            if Task.isCancelled {
                state.cancelled()
                return nil
            }
            switch result {
            case .output(.identity(let raw)):
                return raw.suggestion(from: .mac)
            case .output, .refused:
                return nil
            case .busy:
                guard state.followsOwnCancel else {
                    state.backOff(for: Self.busyRetryAfter)
                    return nil
                }
                try? await Task.sleep(for: retryInterval)
                if Task.isCancelled {
                    state.cancelled()
                    return nil
                }
            case .unavailable:
                // A link failure or a Mac too slow backs off; consent withdrawn, a disconnect or the
                // phone's own scan don't.
                if route.availability == .available, !isPhoneScanning() {
                    state.backOff(for: Self.linkRetryAfter)
                }
                return nil
            }
        }
        return nil
    }

    /// When the Mac may be asked again, and when this phone last gave up on a request.
    private final class RetryState: Sendable {
        private let now: @Sendable () -> ContinuousClock.Instant
        private let times = Mutex<(until: ContinuousClock.Instant?, cancelled: ContinuousClock.Instant?)>((nil, nil))

        init(now: @escaping @Sendable () -> ContinuousClock.Instant) {
            self.now = now
        }

        var isBackingOff: Bool {
            let instant = now()
            return times.withLock { $0.until.map { instant < $0 } ?? false }
        }

        var followsOwnCancel: Bool {
            let instant = now()
            return times.withLock { $0.cancelled.map { instant - $0 < RoutedIdentityService.abandonedWindow } ?? false }
        }

        func backOff(for duration: Duration) {
            let until = now() + duration
            times.withLock { $0.until = until }
        }

        func cancelled() {
            let instant = now()
            times.withLock { $0.cancelled = instant }
        }
    }
}
