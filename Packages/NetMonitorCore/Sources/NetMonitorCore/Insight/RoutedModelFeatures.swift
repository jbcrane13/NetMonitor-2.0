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

    /// As `request`, with why there's no answer: `busy`, or `unavailable` for everything else.
    func result(_ input: ModelInput) async -> ModelClientResult {
        let consent = consent
        guard let generation = consent.allowedGeneration else { return .unavailable }
        let isCurrent: @Sendable () -> Bool = { consent.allowedGeneration == generation }
        let mac = mac
        let work = Task { await mac.request(input, while: isCurrent) }
        let handler = consent.addWithdrawalHandler { work.cancel() }
        defer { consent.removeWithdrawalHandler(handler) }
        // Withdrawn between the check and registering the handler.
        if !isCurrent() {
            work.cancel()
        }
        let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
        return isCurrent() ? result : .unavailable
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
    /// How long the Mac isn't asked after it answered busy or not at all.
    public static let defaultRetryAfter: Duration = .seconds(60)

    public let local: any InsightServiceProtocol
    public let route: MacModelRoute
    private let backoff: Backoff

    public init(
        local: any InsightServiceProtocol, mac: CompanionModelClient, consent: MacInsightConsent, retryAfter: Duration = defaultRetryAfter
    ) {
        self.local = local
        route = MacModelRoute(mac: mac, consent: consent, schema: .identity)
        backoff = Backoff(retryAfter: retryAfter)
    }

    /// The local model, or a Mac offering identity once the user has said yes and not backing off
    /// after a busy or failed answer; never "ask first". `DeviceSuggester` stops its pass, without
    /// recording, when this turns false under it.
    public var isAvailable: Bool { local.isAvailable || (route.availability == .available && !backoff.isActive) }

    public func explain(_ request: InsightRequest) -> AsyncStream<InsightUpdate> {
        local.explain(request)
    }

    public func suggestIdentity(_ evidence: DeviceEvidence) async -> DeviceSuggestion? {
        if local.isAvailable {
            return await local.suggestIdentity(evidence)
        }
        guard route.availability == .available, !backoff.isActive else { return nil }
        guard case .output(.identity(let raw)) = await route.result(.identity(evidence.projection)) else {
            // Busy, gone, too slow or refused: leave the Mac alone for a while. Not when the caller
            // gave up (the user left the screen): the Mac said nothing about being busy.
            if !Task.isCancelled {
                backoff.start()
            }
            return nil
        }
        return raw.suggestion(from: .mac)
    }

    /// When the Mac may be asked again.
    private final class Backoff: Sendable {
        private let retryAfter: Duration
        private let until = Mutex<ContinuousClock.Instant?>(nil)

        init(retryAfter: Duration) {
            self.retryAfter = retryAfter
        }

        var isActive: Bool { until.withLock { $0.map { ContinuousClock.now < $0 } ?? false } }

        func start() {
            until.withLock { $0 = ContinuousClock.now + retryAfter }
        }
    }
}
