import NetMonitorCore
import SwiftUI

/// "Use your Mac for on-device AI?" (#457): asked once, when the user first asks for something
/// this phone's model can't write and a connected Mac could. Until they agree nothing is sent
/// and features fall back.
struct MacInsightConsentAlert: ViewModifier {
    @Binding var isPresented: Bool
    let consent: MacInsightConsent
    /// Runs after the user agrees, such as the explanation they asked for.
    let onAgree: () -> Void

    func body(content: Content) -> some View {
        content.alert("Use your Mac for on-device AI?", isPresented: $isPresented) {
            Button("Use My Mac") {
                consent.agree()
                onAgree()
            }
            .accessibilityIdentifier("macInsight_button_agree")
            Button("Don't Use Mac", role: .cancel) { consent.decline() }
                .accessibilityIdentifier("macInsight_button_decline")
        } message: {
            Text("This iPhone can't run the on-device model. Your Mac's model can write explanations and summaries instead. "
                + "Requests go to your Mac over your local network. You can change this in Settings.")
        }
    }
}

/// The Settings switch for the same answer (#457): shown once the user has answered, or while
/// a connected Mac offers its model.
struct MacInsightSettingsRow: View {
    let routed: RoutedInsightService

    var body: some View {
        if routed.consent.decision != nil || routed.mac.isAvailable {
            Toggle("Use your Mac for on-device AI", isOn: Binding(get: { routed.consent.isAllowed }, set: routed.consent.setAllowed))
                .accessibilityIdentifier("settings_toggle_macInsight")
        }
    }
}

/// "Let your Mac read what you type?" (#586): asked once, the first time the user submits a typed
/// rule or symptom this phone's model can't read and a connected Mac could. A separate answer from
/// explanations: what the user types is a new kind of data to send. Until they agree nothing is
/// sent, and the feature keeps its path without the model.
struct MacReadingConsentAlert: ViewModifier {
    @Binding var isPresented: Bool
    let consent: MacInsightConsent?
    /// Runs after the user agrees: the request they submitted.
    let onAgree: () -> Void

    func body(content: Content) -> some View {
        content.alert("Let your Mac read what you type?", isPresented: $isPresented) {
            Button("Use My Mac") {
                consent?.agree()
                onAgree()
            }
            .accessibilityIdentifier("macReading_button_agree")
            Button("Don't Use Mac", role: .cancel) { consent?.decline() }
                .accessibilityIdentifier("macReading_button_decline")
        } message: {
            Text(MacReadingConsentAlert.message)
        }
    }

    static let message = "This iPhone can't run the on-device model. Your Mac's model can read the rules and problems you type "
        + "here, and, in the background, suggest what your devices are from their names, services, open ports and makers. "
        + "That text and those details go to your Mac over your local network and aren't kept there. You can change this in Settings."
}

/// The Settings switch for the same answer (#586): shown once the user has answered, or while a
/// connected Mac offers to read typed text.
struct MacReadingSettingsRow: View {
    let mac: CompanionModelClient
    let consent: MacInsightConsent

    var body: some View {
        if consent.decision != nil || !mac.offeredSchemas.isEmpty {
            Toggle("Let your Mac read what you type", isOn: Binding(get: { consent.isAllowed }, set: consent.setAllowed))
                .accessibilityIdentifier("settings_toggle_macReading")
        }
    }
}
