import Foundation
import Network
import Testing
@testable import NetworkScanKit

@Suite("withNWConnection")
struct NWConnectionHelperTests {

    @Test("returns timeoutValue when classify never resolves")
    func timeoutPath() async {
        // Endpoint is intentionally unreachable (RFC 5737 TEST-NET-1) so the
        // connection cannot transition to a state classify treats as terminal
        // within the timeout window.
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("192.0.2.1"),
            port: NWEndpoint.Port(rawValue: 65535)!
        )
        let params = NWParameters.tcp
        params.requiredInterfaceType = .wifi
        let connection = NWConnection(to: endpoint, using: params)

        let result = await withNWConnection(
            connection,
            timeout: .milliseconds(100),
            timeoutValue: "timed-out"
        ) { state in
            // Never resolve from any state — force the timeout path.
            _ = state
            return nil
        }

        #expect(result == "timed-out")
    }

    @Test("classify returning .complete returns the value")
    func completePathResolves() async {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 9)!
        )
        let connection = NWConnection(to: endpoint, using: .udp)

        let result = await withNWConnection(
            connection,
            timeout: .seconds(2),
            timeoutValue: "timeout"
        ) { state in
            switch state {
            case .ready: return .complete("ready")
            case .failed, .cancelled: return .complete("error")
            default: return nil
            }
        }

        #expect(result == "ready" || result == "error")
        #expect(result != "timeout")
    }

    @Test("classify returning .completeKeepAlive returns value without cancelling")
    func keepAlivePathLeavesConnection() async {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 9)!
        )
        let connection = NWConnection(to: endpoint, using: .udp)

        let result = await withNWConnection(
            connection,
            timeout: .seconds(2),
            timeoutValue: false
        ) { state in
            switch state {
            case .ready: return .completeKeepAlive(true)
            case .failed, .cancelled: return .complete(false)
            default: return nil
            }
        }

        if result {
            // On keep-alive resolution, the helper must not have cancelled the
            // connection itself. NWConnection.state is read off-actor and the
            // value may lag, so accept anything other than .cancelled here —
            // the contract we care about is "the helper did not call cancel".
            switch connection.state {
            case .cancelled:
                Issue.record("connection was cancelled despite .completeKeepAlive")
            default:
                break
            }
            connection.cancel()
        }
    }

    @Test("nil from classify ignores transient states")
    func nilKeepsWaiting() async {
        // UDP loopback transitions through .preparing (which the classifier
        // ignores) before settling. The test verifies that returning nil for a
        // state does not cause a premature resolve — i.e. we eventually reach
        // .ready (or .failed) rather than the timeout fallback.
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: 9)!
        )
        let connection = NWConnection(to: endpoint, using: .udp)

        let result: String = await withNWConnection(
            connection,
            timeout: .seconds(2),
            timeoutValue: "timeout"
        ) { state in
            switch state {
            case .ready: return .complete("ready")
            case .failed, .cancelled: return .complete("error")
            default: return nil  // .setup, .preparing — keep waiting
            }
        }

        #expect(result != "timeout", "should resolve via .ready or .failed, not timeout")
    }
}
