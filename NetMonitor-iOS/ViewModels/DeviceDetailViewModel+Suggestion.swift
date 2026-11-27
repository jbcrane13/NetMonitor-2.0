import Foundation
import NetMonitorCore

// MARK: - Suggestion scheduling (#642 review)

extension DeviceDetailViewModel {
    /// Asks the on-device model about the loaded row without blocking the load. Called again
    /// when enrichment, a port scan or service discovery changes the evidence; a pass already
    /// started on the same evidence keeps running.
    func startSuggestion() {
        refreshSuggestionState()
        guard let device else {
            return
        }
        let fingerprint = DeviceEvidence(device: device).fingerprint
        guard fingerprint != suggestionFingerprint else {
            return
        }
        suggestionFingerprint = fingerprint
        suggestionTask?.cancel()
        suggestionRetryTask?.cancel()
        let discovery = deviceDiscoveryService
        suggestionTask = Task { [weak self, suggester] in
            // Ask once the evidence has settled: enrichment, service discovery and a port scan
            // change it in quick succession, and a later change cancels this before anything is
            // sent (#642 review).
            try? await Task.sleep(for: Self.suggestionSettle)
            guard !Task.isCancelled else {
                return
            }
            await Self.suggestOutsideScans(device, suggester: suggester, discovery: discovery)
            guard !Task.isCancelled, let self else {
                return
            }
            // Not answered (a busy or gone Mac): the next call asks again, once the Mac's back-off
            // is over, instead of skipping this evidence as already asked about (#586).
            if !suggester.wasAsked(about: device) {
                self.suggestionFingerprint = nil
                self.retrySuggestionWhenAskable()
            }
            self.saveContext()
            self.refreshSuggestionState()
        }
    }

    /// How long the evidence must stay unchanged before the model is asked.
    static let suggestionSettle: Duration = .milliseconds(800)
    /// How often a waiting suggestion checks whether the phone's scan is over.
    static let scanPoll: Duration = .milliseconds(250)

    /// Runs the suggestion pass for `device`, never during the phone's own scan (#447): it waits for
    /// a scan to end, and a scan that starts meanwhile cancels the pass (which records nothing), to
    /// run it again once that scan is over.
    static func suggestOutsideScans(
        _ device: LocalDevice, suggester: DeviceSuggester, discovery: any DeviceDiscoveryServiceProtocol
    ) async {
        while !Task.isCancelled {
            while discovery.isScanning {
                try? await Task.sleep(for: scanPoll)
                if Task.isCancelled {
                    return
                }
            }
            let finished = PassFlag()
            let pass = Task {
                await suggester.suggest(for: [device])
                finished.isDone = true
            }
            var interrupted = false
            while !finished.isDone, !Task.isCancelled {
                if discovery.isScanning {
                    pass.cancel()
                    interrupted = true
                    break
                }
                try? await Task.sleep(for: scanPoll)
            }
            if Task.isCancelled {
                pass.cancel()
            }
            await pass.value
            if !interrupted {
                return
            }
        }
    }

    /// Set when a suggestion pass has finished.
    @MainActor
    final class PassFlag {
        var isDone = false
    }

    /// How often the open screen checks whether the Mac can be asked again.
    static let retryPoll: Duration = .seconds(1)

    /// After a pass that got no answer (the Mac busy or backing off, consent withdrawn, the Mac
    /// gone): asks once more as soon as a suggestion can be asked for again, while the screen is
    /// open, without the user reopening it (#642 final check).
    func retrySuggestionWhenAskable() {
        suggestionRetryTask?.cancel()
        suggestionRetryTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.retryPoll)
                guard !Task.isCancelled, let self else {
                    return
                }
                if self.suggesterCanSuggest {
                    self.startSuggestion()
                    return
                }
            }
        }
    }
}
