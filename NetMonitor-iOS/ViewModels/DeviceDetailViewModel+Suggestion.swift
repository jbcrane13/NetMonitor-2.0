import Foundation
import NetMonitorCore

// MARK: - Suggestion scheduling (#642 review)

extension DeviceDetailViewModel {
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
