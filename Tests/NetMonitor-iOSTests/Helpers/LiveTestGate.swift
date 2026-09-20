import Foundation

/// Gates test suites that need a real LAN, live Bonjour peers, or other
/// environment-dependent resources that cannot be made deterministic in place.
///
/// Set `NETMONITOR_LIVE_TESTS=1` in the test process environment to enable them
/// (via xcodebuild, `TEST_RUNNER_NETMONITOR_LIVE_TESTS=1` — only `TEST_RUNNER_`-prefixed
/// variables are forwarded into the test process).
///
/// Not to be confused with `NETMONITOR_LIVE_SCAN`, which gates
/// `DeviceDiscoveryCoordinatorLiveScanTests` specifically (running the live discovery
/// scan) — the two flags have different meanings and neither substitutes for the other.
enum LiveTestGate {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["NETMONITOR_LIVE_TESTS"] == "1"
    }
}
