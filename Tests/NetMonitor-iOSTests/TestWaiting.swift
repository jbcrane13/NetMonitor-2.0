import Foundation

/// Polls `condition` every 10 ms until it returns `true` or `timeout` elapses.
///
/// Use instead of `Task.sleep(for: .milliseconds(N))` when waiting for ViewModel
/// state changes on the main actor. Fixed delays are flaky under parallel load
/// because the ViewModel's child task may not be scheduled within the deadline.
@MainActor
func waitUntil(_ condition: @MainActor () -> Bool, timeout: Duration = .seconds(2)) async {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        guard ContinuousClock.now < deadline else { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}
