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
}
