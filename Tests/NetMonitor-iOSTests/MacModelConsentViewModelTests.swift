import Foundation
import NetMonitorCore
import Testing
@testable import NetMonitor_iOS

/// Whether the rule field and the troubleshooter ask "Let your Mac read what you type?" first (#586).
@Suite("Mac-read consent in the view models")
@MainActor
struct MacModelConsentViewModelTests {
    private func mac(offering capabilities: [String]) -> CompanionModelClient {
        let client = CompanionModelClient(send: { _, _ in false })
        client.received(heartbeat: HeartbeatPayload(capabilities: capabilities), onLink: UUID())
        return client
    }

    private func env() -> AppEnvironment {
        AppEnvironment(
            networkMonitor: MockNetworkMonitorService(), deviceDiscovery: MockDeviceDiscoveryService(),
            macConnection: MockMacConnectionService(), publicIP: MockPublicIPService(), wifiInfo: MockWiFiInfoService(),
            targetManager: .shared, activityLog: .shared, eventService: NetworkEventService(), scanScheduler: ScanSchedulerService.shared
        )
    }

    @Test func theRuleFieldAsksOnlyBeforeTheUserHasAnswered() {
        let client = mac(offering: ["rules.v1"])
        let consent = MacInsightConsent(defaults: nil)
        let parser = RoutedRuleIntentParser(local: UnavailableRuleIntentParser(), mac: client, consent: consent)
        let viewModel = PlainRuleIOSViewModel(parser: parser)
        #expect(viewModel.isAvailable)
        #expect(viewModel.needsMacConsent)
        consent.agree()
        #expect(!viewModel.needsMacConsent)
        consent.decline()
        #expect(!viewModel.isAvailable, "declined: no field")

        let local = RoutedRuleIntentParser(
            local: FixedRuleIntentParser(answers: [:]), mac: client, consent: MacInsightConsent(defaults: nil)
        )
        #expect(!PlainRuleIOSViewModel(parser: local).needsMacConsent, "this phone's own model never asks")
    }

    @Test func theTroubleshooterAsksOnlyBeforeTheUserHasAnswered() {
        let client = mac(offering: ["symptoms.v1"])
        let consent = MacInsightConsent(defaults: nil)
        let classifier = RoutedSymptomClassifier(local: UnavailableSymptomClassifier(), mac: client, consent: consent)
        let viewModel = TroubleshootToolViewModel(env: env(), mode: nil, classifier: classifier)
        #expect(viewModel.state.canDescribe)
        #expect(viewModel.needsMacConsent)
        consent.agree()
        #expect(!viewModel.needsMacConsent)

        let noMac = RoutedSymptomClassifier(local: UnavailableSymptomClassifier(), mac: mac(offering: []), consent: consent)
        #expect(!TroubleshootToolViewModel(env: env(), mode: nil, classifier: noMac).state.canDescribe, "no capable Mac: buttons only")
    }
}
